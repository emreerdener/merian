-- Inactive private-evidence operations. No schedule, gate or credential changes.
SET lock_timeout = '5s';
SET statement_timeout = '2min';

-- Existing rows have unknown original enqueue age. Do not invent it from the
-- retry timestamp or rewrite historical rows. New obligations retain this clock.
ALTER TABLE internal.observation_evidence_erasure
    ADD COLUMN first_observed_at TIMESTAMPTZ;
ALTER TABLE internal.observation_evidence_erasure
    ALTER COLUMN first_observed_at SET DEFAULT clock_timestamp();
CREATE INDEX observation_evidence_erasure_observed_pending
    ON internal.observation_evidence_erasure(first_observed_at)
    WHERE erased_at IS NULL;

CREATE FUNCTION internal.preserve_evidence_erasure_observed_at()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY INVOKER SET search_path = '' AS $$
BEGIN
    IF NEW.first_observed_at IS DISTINCT FROM OLD.first_observed_at THEN
        RAISE EXCEPTION 'evidence_erasure_observation_clock_immutable' USING ERRCODE = '22023';
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.preserve_evidence_erasure_observed_at()
    FROM PUBLIC, anon, authenticated, service_role;
CREATE TRIGGER preserve_evidence_erasure_observed_at
    BEFORE UPDATE ON internal.observation_evidence_erasure
    FOR EACH ROW EXECUTE FUNCTION internal.preserve_evidence_erasure_observed_at();

-- Aggregate observation only. SQL retirement owners still revalidate under
-- their original source/parent locks. These candidates confer no authority.
CREATE FUNCTION internal.observation_evidence_retirement_candidates(p_observed_at TIMESTAMPTZ)
RETURNS TABLE(kind TEXT, analysis_id UUID, media_id UUID, expires_at TIMESTAMPTZ, object_count BIGINT)
LANGUAGE SQL STABLE SECURITY INVOKER SET search_path = '' AS $$
    SELECT due.kind, due.analysis_id, due.media_id, due.expires_at,
        (SELECT count(*) FROM internal.observation_evidence_objects object
         WHERE object.analysis_id = due.analysis_id
           AND (due.kind <> 'orphan' OR object.media_id = due.media_id))
    FROM (
        SELECT 'photo'::TEXT AS kind, c.owner_id,c.observation_id,c.analysis_id,NULL::UUID AS media_id,c.expires_at
        FROM internal.observation_evidence_upload_cohorts c
        WHERE c.expires_at <= p_observed_at
          AND internal.valid_observation_erasure_cohort_items(c.items)
          AND NOT EXISTS(SELECT 1 FROM internal.observation_evidence_objects e WHERE e.analysis_id=c.analysis_id
              AND (e.owner_id<>c.owner_id OR e.observation_id<>c.observation_id OR e.expires_at<>c.expires_at
                  OR NOT(c.items @> jsonb_build_array(jsonb_build_object('media_id',e.media_id,'content_type',e.content_type,'byte_count',e.byte_count,'sha256',e.sha256)))))
          AND EXISTS(SELECT 1 FROM internal.observation_evidence_objects e WHERE e.analysis_id=c.analysis_id)
        UNION ALL
        SELECT 'audio'::TEXT,a.owner_id,a.observation_id,a.analysis_id,a.media_id,a.expires_at
        FROM internal.observation_audio_evidence_upload_cohorts a
        JOIN internal.observation_evidence_objects e ON e.analysis_id=a.analysis_id AND e.media_id=a.media_id
          AND e.owner_id=a.owner_id AND e.observation_id=a.observation_id AND e.object_id=a.object_id
          AND e.content_type=a.content_type AND e.byte_count=a.byte_count AND e.sha256=a.sha256 AND e.expires_at=a.expires_at
        WHERE a.expires_at <= p_observed_at
          AND NOT EXISTS(SELECT 1 FROM internal.observation_evidence_objects extra WHERE extra.analysis_id=a.analysis_id AND extra.media_id<>a.media_id)
        UNION ALL
        SELECT 'orphan'::TEXT,e.owner_id,e.observation_id,e.analysis_id,e.media_id,e.expires_at
        FROM internal.observation_evidence_objects e
        WHERE e.expires_at <= p_observed_at
          AND NOT EXISTS(SELECT 1 FROM internal.observation_evidence_upload_cohorts c WHERE c.analysis_id=e.analysis_id)
          AND NOT EXISTS(SELECT 1 FROM internal.observation_audio_evidence_upload_cohorts a WHERE a.analysis_id=e.analysis_id)
          AND NOT EXISTS(SELECT 1 FROM internal.observation_video_evidence_allocations v WHERE v.analysis_id=e.analysis_id)
        UNION ALL
        SELECT 'video'::TEXT,v.owner_id,v.observation_id,v.analysis_id,NULL::UUID,v.expires_at
        FROM internal.observation_video_evidence_allocations v
        WHERE v.expires_at <= p_observed_at
          AND EXISTS(SELECT 1 FROM internal.observation_evidence_objects e WHERE e.analysis_id=v.analysis_id)
          AND internal.observation_video_evidence_execution_clear(v.analysis_id)
    ) due
    WHERE NOT EXISTS(SELECT 1 FROM internal.observation_analysis_intents i WHERE i.analysis_id=due.analysis_id)
      AND NOT EXISTS(SELECT 1 FROM internal.observation_analysis_results r WHERE r.analysis_id=due.analysis_id)
      AND EXISTS(SELECT 1 FROM public.scans s WHERE s.id=due.observation_id AND s.user_id=due.owner_id AND NOT s.is_tombstoned)
      AND NOT EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones t WHERE t.scan_id=due.observation_id);
$$;
REVOKE ALL ON FUNCTION internal.observation_evidence_retirement_candidates(TIMESTAMPTZ)
    FROM PUBLIC, anon, authenticated, service_role;

-- One bounded transport slot. An unknown/missing asynchronous result holds the
-- slot for explicit reconciliation instead of silently launching overlapping
-- requests. No response body, credential or object identity is retained here.
CREATE TABLE internal.observation_evidence_worker_state (
    singleton BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (singleton),
    enabled BOOLEAN NOT NULL DEFAULT FALSE,
    approved_project TEXT CHECK (approved_project ~ '^[a-z0-9]{20}$'),
    pending_request_id BIGINT,
    last_dispatched_at TIMESTAMPTZ,
    last_observed_at TIMESTAMPTZ,
    last_completed_at TIMESTAMPTZ,
    last_success_at TIMESTAMPTZ,
    last_marker_success_at TIMESTAMPTZ,
    last_http_status INTEGER,
    last_result TEXT NOT NULL DEFAULT 'never' CHECK (last_result IN ('never','pending','success','failure','unknown','configuration_unavailable')),
    consecutive_failures INTEGER NOT NULL DEFAULT 0 CHECK (consecutive_failures >= 0),
    last_retired INTEGER CHECK (last_retired BETWEEN 0 AND 5),
    last_video_retired INTEGER CHECK (last_video_retired BETWEEN 0 AND 7),
    last_retirement_failures INTEGER CHECK (last_retirement_failures BETWEEN 0 AND 2),
    last_claimed INTEGER CHECK (last_claimed BETWEEN 0 AND 1),
    last_marked INTEGER CHECK (last_marked BETWEEN 0 AND 1),
    last_acknowledged INTEGER CHECK (last_acknowledged BETWEEN 0 AND 1)
);
ALTER TABLE internal.observation_evidence_worker_state ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON internal.observation_evidence_worker_state FROM PUBLIC, anon, authenticated, service_role;
INSERT INTO internal.observation_evidence_worker_state(singleton) VALUES (TRUE);

-- Ephemeral privileged transport configuration. Never exposed in health output.
-- An explicitly blank Vault value does not fall through to a setting.
CREATE FUNCTION internal.observation_evidence_worker_transport(p_project TEXT)
RETURNS JSONB LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path = '' AS $$
DECLARE project_url TEXT; server_key TEXT; request_headers JSONB;
BEGIN
    IF p_project IS NULL OR p_project !~ '^[a-z0-9]{20}$' THEN RETURN NULL; END IF;
    SELECT decrypted_secret INTO project_url FROM vault.decrypted_secrets WHERE name='SUPABASE_URL' LIMIT 1;
    SELECT decrypted_secret INTO server_key FROM vault.decrypted_secrets WHERE name='SUPABASE_SERVICE_ROLE_KEY' LIMIT 1;
    IF project_url IS NULL THEN project_url := current_setting('app.settings.supabase_url',TRUE); END IF;
    IF server_key IS NULL THEN server_key := current_setting('app.settings.supabase_service_role_key',TRUE); END IF;
    IF project_url IS DISTINCT FROM 'https://' || p_project || '.supabase.co' THEN RETURN NULL; END IF;
    BEGIN
        request_headers := internal.server_api_request_headers(server_key);
    EXCEPTION WHEN invalid_parameter_value THEN RETURN NULL;
    END;
    RETURN jsonb_build_object('url',project_url || '/functions/v1/erase-observation-evidence','headers',request_headers);
END;
$$;
REVOKE ALL ON FUNCTION internal.observation_evidence_worker_transport(TEXT)
    FROM PUBLIC, anon, authenticated, service_role;

-- Closed aggregate worker receipt. Malformed, partial, timeout and missing
-- acknowledgements cannot become a successful drain heartbeat.
CREATE FUNCTION internal.valid_observation_evidence_worker_receipt(p_receipt JSONB)
RETURNS BOOLEAN LANGUAGE PLPGSQL IMMUTABLE SECURITY INVOKER SET search_path = '' AS $$
DECLARE field TEXT;
BEGIN
    IF p_receipt IS NULL OR jsonb_typeof(p_receipt) IS DISTINCT FROM 'object' THEN RETURN FALSE; END IF;
    IF (SELECT count(*) FROM jsonb_object_keys(p_receipt)) <> 6 THEN RETURN FALSE; END IF;
    FOREACH field IN ARRAY ARRAY['retired','video_retired','retirement_failures','claimed','marked','acknowledged'] LOOP
        IF jsonb_typeof(p_receipt->field) IS DISTINCT FROM 'number'
           OR (p_receipt->>field) !~ '^[0-9]$' THEN RETURN FALSE; END IF;
    END LOOP;
    RETURN (p_receipt->>'retired')::INTEGER <= 5
       AND (p_receipt->>'video_retired')::INTEGER <= 7
       AND (p_receipt->>'retirement_failures')::INTEGER <= 2
       AND (p_receipt->>'claimed')::INTEGER <= 1
       AND (p_receipt->>'marked')::INTEGER <= (p_receipt->>'claimed')::INTEGER
       AND (p_receipt->>'acknowledged')::INTEGER <= (p_receipt->>'claimed')::INTEGER;
END;
$$;
REVOKE ALL ON FUNCTION internal.valid_observation_evidence_worker_receipt(JSONB)
    FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION internal.dispatch_observation_evidence_erasure()
RETURNS VOID LANGUAGE PLPGSQL SECURITY INVOKER SET search_path = '' SET statement_timeout = '5s' AS $$
DECLARE
    state internal.observation_evidence_worker_state%ROWTYPE;
    response net._http_response%ROWTYPE;
    receipt JSONB;
    transport JSONB;
    observed_at TIMESTAMPTZ := clock_timestamp();
    succeeded BOOLEAN := FALSE;
    valid_receipt BOOLEAN := FALSE;
    request_id BIGINT;
BEGIN
    -- The durable slot survives the transaction and covers asynchronous work.
    SELECT * INTO state FROM internal.observation_evidence_worker_state WHERE singleton FOR UPDATE SKIP LOCKED;
    IF NOT FOUND THEN RETURN; END IF;
    IF state.pending_request_id IS NOT NULL THEN
        SELECT * INTO response FROM net._http_response WHERE id=state.pending_request_id;
        IF NOT FOUND OR response.timed_out IS TRUE OR response.error_msg IS NOT NULL THEN
            UPDATE internal.observation_evidence_worker_state
            SET last_observed_at=observed_at,
                last_result=CASE WHEN observed_at-last_dispatched_at >= INTERVAL '3 minutes'
                    OR response.timed_out IS TRUE OR response.error_msg IS NOT NULL THEN 'unknown' ELSE 'pending' END
            WHERE singleton;
            RETURN;
        END IF;
        -- Bounded parse; never persist or emit content/headers/error strings.
        IF response.status_code=200 AND octet_length(response.content) <= 2048
           AND isfinite(response.created) AND response.created >= state.last_dispatched_at
           AND response.created <= observed_at THEN
            BEGIN
                receipt := response.content::JSONB;
                valid_receipt := internal.valid_observation_evidence_worker_receipt(receipt);
            EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN valid_receipt := FALSE;
            END;
        END IF;
        IF NOT valid_receipt THEN
            -- Proxy errors and malformed/uncorrelated bodies do not prove that
            -- the remote worker stopped. Keep the original slot until reviewed
            -- quiescence/reconciliation; elapsed time is not that proof.
            UPDATE internal.observation_evidence_worker_state
            SET last_observed_at=observed_at,last_result='unknown',last_http_status=response.status_code
            WHERE singleton;
            RETURN;
        END IF;
        succeeded := (receipt->>'retirement_failures')::INTEGER=0
            AND receipt->>'claimed'=receipt->>'marked' AND receipt->>'claimed'=receipt->>'acknowledged';
        UPDATE internal.observation_evidence_worker_state
        SET pending_request_id=NULL,last_observed_at=observed_at,last_completed_at=response.created,
            last_http_status=response.status_code,last_result=CASE WHEN succeeded THEN 'success' ELSE 'failure' END,
            last_success_at=CASE WHEN succeeded THEN response.created ELSE last_success_at END,
            last_marker_success_at=CASE WHEN succeeded AND receipt->>'marked'='1' THEN response.created ELSE last_marker_success_at END,
            consecutive_failures=CASE WHEN succeeded THEN 0 ELSE least(consecutive_failures,2147483646)+1 END,
            last_retired=CASE WHEN valid_receipt THEN (receipt->>'retired')::INTEGER END,
            last_video_retired=CASE WHEN valid_receipt THEN (receipt->>'video_retired')::INTEGER END,
            last_retirement_failures=CASE WHEN valid_receipt THEN (receipt->>'retirement_failures')::INTEGER END,
            last_claimed=CASE WHEN valid_receipt THEN (receipt->>'claimed')::INTEGER END,
            last_marked=CASE WHEN valid_receipt THEN (receipt->>'marked')::INTEGER END,
            last_acknowledged=CASE WHEN valid_receipt THEN (receipt->>'acknowledged')::INTEGER END
        WHERE singleton;
    END IF;
    -- Pausing stops new transport; an existing result can still be reconciled.
    IF NOT state.enabled THEN RETURN; END IF;
    transport := internal.observation_evidence_worker_transport(state.approved_project);
    IF transport IS NULL THEN
        UPDATE internal.observation_evidence_worker_state
        SET last_observed_at=observed_at,last_result='configuration_unavailable' WHERE singleton;
        RETURN;
    END IF;
    SELECT net.http_post(url:=transport->>'url',headers:=transport->'headers',body:='{}'::JSONB,
        timeout_milliseconds:=120000) INTO request_id;
    IF request_id IS NULL THEN RAISE EXCEPTION 'evidence_worker_dispatch_unacknowledged'; END IF;
    UPDATE internal.observation_evidence_worker_state
    SET pending_request_id=request_id,last_dispatched_at=observed_at,last_observed_at=observed_at
    WHERE singleton;
END;
$$;
REVOKE ALL ON FUNCTION internal.dispatch_observation_evidence_erasure()
    FROM PUBLIC, anon, authenticated, service_role;

CREATE FUNCTION public.get_observation_evidence_erasure_health()
RETURNS JSONB LANGUAGE PLPGSQL STABLE SECURITY DEFINER SET search_path = '' SET statement_timeout = '5s' AS $$
DECLARE
    observed_at TIMESTAMPTZ := statement_timestamp();
    queue JSONB; candidates JSONB; telemetry JSONB;
    state internal.observation_evidence_worker_state%ROWTYPE;
BEGIN
    PERFORM internal.require_service_role();
    SELECT * INTO STRICT state FROM internal.observation_evidence_worker_state WHERE singleton;
    SELECT jsonb_build_object(
        'pending',count(*) FILTER(WHERE erased_at IS NULL),
        'claimable',count(*) FILTER(WHERE erased_at IS NULL AND available_at<=observed_at AND (claim_expires_at IS NULL OR claim_expires_at<=observed_at)),
        'deferred',count(*) FILTER(WHERE erased_at IS NULL AND available_at>observed_at AND (claim_expires_at IS NULL OR claim_expires_at<=observed_at)),
        'live_claims',count(*) FILTER(WHERE erased_at IS NULL AND claim_expires_at>observed_at),
        'expired_claims',count(*) FILTER(WHERE erased_at IS NULL AND claim_expires_at<=observed_at),
        'unknown_age',count(*) FILTER(WHERE erased_at IS NULL AND first_observed_at IS NULL),
        'oldest_pending_age_seconds',greatest(0,extract(epoch FROM observed_at-min(first_observed_at) FILTER(WHERE erased_at IS NULL))),
        'oldest_due_age_seconds',greatest(0,extract(epoch FROM observed_at-min(available_at) FILTER(WHERE erased_at IS NULL AND available_at<=observed_at AND (claim_expires_at IS NULL OR claim_expires_at<=observed_at))))
    ) INTO queue FROM internal.observation_evidence_erasure;
    WITH due AS MATERIALIZED (SELECT * FROM internal.observation_evidence_retirement_candidates(observed_at))
    SELECT jsonb_build_object('photo',count(*) FILTER(WHERE kind='photo'),
        'audio',count(*) FILTER(WHERE kind='audio'),'video',count(*) FILTER(WHERE kind='video'),
        'orphan',count(*) FILTER(WHERE kind='orphan'),'objects',coalesce(sum(object_count),0),
        'oldest_age_seconds',greatest(0,extract(epoch FROM observed_at-min(expires_at))),
        'expired_bound_objects',(SELECT count(*) FROM internal.observation_evidence_objects e
            WHERE e.expires_at<=observed_at AND (EXISTS(SELECT 1 FROM internal.observation_analysis_intents i WHERE i.analysis_id=e.analysis_id)
                OR EXISTS(SELECT 1 FROM internal.observation_analysis_results r WHERE r.analysis_id=e.analysis_id))),
        'expired_unretirable_objects',(SELECT count(*) FROM internal.observation_evidence_objects e
            WHERE e.expires_at<=observed_at
              AND NOT EXISTS(SELECT 1 FROM internal.observation_analysis_intents i WHERE i.analysis_id=e.analysis_id)
              AND NOT EXISTS(SELECT 1 FROM internal.observation_analysis_results r WHERE r.analysis_id=e.analysis_id)
              AND NOT EXISTS(SELECT 1 FROM due d
                WHERE d.analysis_id=e.analysis_id AND (d.kind<>'orphan' OR d.media_id=e.media_id))))
    INTO candidates FROM due;
    telemetry := jsonb_build_object('enabled',state.enabled,
        'cron_active',EXISTS(SELECT 1 FROM cron.job WHERE jobname='observation_evidence_erasure_every_minute'
            AND active AND schedule='* * * * *' AND command='SELECT internal.dispatch_observation_evidence_erasure();'
            AND username='postgres' AND database=current_database()),
        'credentials_ready',internal.observation_evidence_worker_transport(state.approved_project) IS NOT NULL,
        'admission_enabled',(SELECT private_evidence_erasure_enabled FROM internal.observation_history_rollout),
        'request_pending',state.pending_request_id IS NOT NULL,
        'request_age_seconds',CASE WHEN state.pending_request_id IS NOT NULL THEN greatest(0,extract(epoch FROM observed_at-state.last_dispatched_at)) END,
        'last_result',state.last_result,'consecutive_failures',state.consecutive_failures,
        'success_age_seconds',CASE WHEN state.last_success_at IS NOT NULL THEN greatest(0,extract(epoch FROM observed_at-state.last_success_at)) END,
        'marker_success_age_seconds',CASE WHEN state.last_marker_success_at IS NOT NULL THEN greatest(0,extract(epoch FROM observed_at-state.last_marker_success_at)) END);
    RETURN jsonb_build_object('schema_version',1,'generated_at',observed_at,'queue',queue,'retirement',candidates,'worker',telemetry);
END;
$$;
ALTER FUNCTION public.get_observation_evidence_erasure_health() OWNER TO postgres;
REVOKE ALL ON FUNCTION public.get_observation_evidence_erasure_health() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_observation_evidence_erasure_health() TO service_role;
INSERT INTO internal.privileged_routine_grants(role_name,routine_signature,purpose)
VALUES ('service_role','public.get_observation_evidence_erasure_health()',
    'Read-only aggregate private evidence backlog, blocked retirement, inactive schedule and sanitized bounded worker acknowledgement health');

-- Activation is an explicit operation on the approved beta project. This
-- migration intentionally neither creates a cron job nor enables any gate.
RESET statement_timeout;
RESET lock_timeout;
