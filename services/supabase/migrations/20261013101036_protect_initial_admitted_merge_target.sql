-- Preserve the original funding of target-owned admitted media before any Ghost
-- merge side effect. This is a denial-only prerequisite for private handoff v2;
-- it creates no new admission, settlement, execution or API authority.

CREATE FUNCTION internal.initial_merge_target_admitted_scans(p_owner UUID)
RETURNS SETOF UUID LANGUAGE PLPGSQL STABLE SECURITY INVOKER SET search_path='' AS $$
DECLARE member RECORD;
BEGIN
    -- Catalog values are fixed private constants. Ownership comes only from
    -- relational owner_id, never from a saved canonical document. The same
    -- private-family catalog is extended when handoff children are installed.
    FOR member IN SELECT relation_name FROM internal.initial_cancellation_private_catalog() LOOP
        IF EXISTS(SELECT 1 FROM pg_catalog.pg_attribute
            WHERE attrelid=member.relation_name::REGCLASS AND attname='owner_id' AND NOT attisdropped) THEN
            RETURN QUERY EXECUTE format(
                'SELECT t.scan_id FROM %s t WHERE t.owner_id=$1 AND internal.initial_admitted_settlement_blocked(t.scan_id)',
                member.relation_name) USING p_owner;
        END IF;
    END LOOP;
    RETURN QUERY
    SELECT c.scan_id FROM internal.initial_analysis_cancellations c
        WHERE c.owner_id=p_owner AND internal.initial_admitted_settlement_blocked(c.scan_id)
    UNION
    SELECT identity.scan_id FROM internal.ai_quota_reservations q
        CROSS JOIN LATERAL (VALUES(q.request_id),(q.original_analysis_id),(q.complimentary_client_scan_id)) identity(scan_id)
        WHERE q.user_id=p_owner AND identity.scan_id IS NOT NULL
            AND internal.initial_admitted_settlement_blocked(identity.scan_id)
    UNION
    SELECT u.client_scan_id FROM internal.complimentary_scan_usage u
        WHERE u.user_id=p_owner AND internal.initial_admitted_settlement_blocked(u.client_scan_id);
END;
$$;

-- Dedicated terminal lock path: the live preparation lock helper deliberately
-- rejects cancellation, so it must not be reused or weakened for this check.
-- Both public-user locks and ALL candidate ingestion advisory locks precede it.
CREATE FUNCTION internal.lock_initial_merge_target_terminal(p_owner UUID,p_scan UUID)
RETURNS VOID LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE q internal.ai_quota_reservations; member RECORD; present BOOLEAN;
BEGIN
    PERFORM id FROM public.scans WHERE id=p_scan FOR UPDATE;
    PERFORM observation_id FROM internal.observation_histories WHERE observation_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_analysis_lifecycle_fences WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_analysis_preparation_intents WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_analysis_submissions WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_analysis_cancellations WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_analysis_admissions WHERE scan_id=p_scan FOR UPDATE;

    -- Multiple/foreign aliases are contradictory evidence, not candidates for
    -- duplicate reconciliation. The subsequent stable predicate denies them.
    FOR q IN SELECT * FROM internal.ai_quota_reservations r
        WHERE r.user_id=p_owner AND (r.request_id=p_scan OR r.original_analysis_id=p_scan OR r.complimentary_client_scan_id=p_scan)
        ORDER BY r.id FOR UPDATE LOOP
        PERFORM reservation_id FROM internal.identification_provider_attempts
            WHERE reservation_id=q.id ORDER BY attempt_count FOR UPDATE;
        PERFORM reservation_id FROM internal.ai_quota_reservation_counters l WHERE l.reservation_id=q.id
            ORDER BY CASE l.scope_type WHEN 'user_daily' THEN 1 WHEN 'user_rate' THEN 2 WHEN 'ip_rate' THEN 3 ELSE 4 END,
                l.scope_key,l.bucket,l.window_start FOR UPDATE;
        IF FOUND THEN
            RAISE EXCEPTION 'ghost_merge_target_initial_analysis_requires_attention' USING ERRCODE='55000';
        END IF;
    END LOOP;
    PERFORM client_scan_id FROM internal.complimentary_scan_usage
        WHERE user_id=p_owner AND client_scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_preparation_source_fences WHERE scan_id=p_scan FOR UPDATE;
    PERFORM object_id FROM internal.initial_preparation_source_registry WHERE scan_id=p_scan ORDER BY object_id FOR UPDATE;
    PERFORM object_id FROM internal.initial_preparation_source_mapping WHERE scan_id=p_scan ORDER BY ordinal FOR UPDATE;
    PERFORM scan_id FROM internal.initial_preparation_admission_receipts WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_preparation_source_verifications WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_preparation_execution_grants WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_preparation_output_manifests WHERE scan_id=p_scan FOR UPDATE;
    PERFORM object_id FROM internal.initial_preparation_output_mapping WHERE scan_id=p_scan ORDER BY ordinal FOR UPDATE;
    PERFORM scan_id FROM internal.initial_preparation_outcomes WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_analysis_media_allocation_fences WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_analysis_media_cohorts WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_analysis_media_preparations WHERE scan_id=p_scan FOR UPDATE;
    PERFORM scan_id FROM internal.initial_analysis_media_verifications WHERE scan_id=p_scan FOR UPDATE;
    PERFORM object_id FROM internal.initial_analysis_media_registry WHERE scan_id=p_scan ORDER BY object_id FOR UPDATE;
    -- No private member may survive a terminal exception. The owner/advisory
    -- entry fences protect absence; this does not claim to lock absent rows.
    FOR member IN SELECT relation_name FROM internal.initial_cancellation_private_catalog() LOOP
        EXECUTE format('SELECT EXISTS(SELECT 1 FROM %s WHERE scan_id=$1)',member.relation_name) INTO present USING p_scan;
        IF present THEN RAISE EXCEPTION 'ghost_merge_target_initial_analysis_requires_attention' USING ERRCODE='55000'; END IF;
    END LOOP;
    PERFORM internal.assert_initial_cancellation_transients_absent(p_scan);
    IF EXISTS(SELECT 1 FROM internal.initial_preparation_admission_staging WHERE scan_id=p_scan)
        OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_writes WHERE scan_id=p_scan) THEN
        RAISE EXCEPTION 'ghost_merge_target_initial_analysis_requires_attention' USING ERRCODE='55000';
    END IF;
END;
$$;

CREATE FUNCTION internal.assert_initial_merge_target_terminal(p_source UUID,p_owner UUID,p_scan UUID)
RETURNS VOID LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE q internal.ai_quota_reservations; attempt internal.identification_provider_attempts;
    usage_row internal.complimentary_scan_usage; member RECORD; present BOOLEAN;
BEGIN
    -- Read again only after the complete actual-row lock scope. Cancellation
    -- establishes the original owner; a permanent fence alone never does.
    IF NOT EXISTS(SELECT 1 FROM internal.initial_analysis_cancellations
            WHERE scan_id=p_scan AND owner_id=p_owner AND dispatch='dispatch_prevented')
        OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_lifecycle_fences
            WHERE scan_id=p_scan AND state='cancelled_pre_dispatch')
        OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_operation_fences WHERE scan_id=p_scan)
        OR NOT EXISTS(SELECT 1 FROM internal.initial_preparation_source_fences
            WHERE scan_id=p_scan AND state='retired' AND provider_barrier='blocked_pre_admission')
        OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_media_allocation_fences
            WHERE scan_id=p_scan AND state='retired')
        OR NOT EXISTS(SELECT 1 FROM internal.initial_preparation_source_registry WHERE scan_id=p_scan)
        OR NOT EXISTS(SELECT 1 FROM internal.initial_analysis_media_registry WHERE scan_id=p_scan)
        OR EXISTS(SELECT 1 FROM internal.initial_preparation_source_registry WHERE scan_id=p_scan AND NOT retired)
        OR EXISTS(SELECT 1 FROM internal.initial_analysis_media_registry WHERE scan_id=p_scan AND NOT retired)
        OR EXISTS(SELECT 1 FROM public.scans WHERE id=p_scan)
        OR EXISTS(SELECT 1 FROM internal.observation_histories WHERE observation_id=p_scan) THEN
        RAISE EXCEPTION 'ghost_merge_target_initial_analysis_requires_attention' USING ERRCODE='55000';
    END IF;
    FOR member IN SELECT relation_name FROM internal.initial_cancellation_private_catalog() LOOP
        EXECUTE format('SELECT EXISTS(SELECT 1 FROM %s WHERE scan_id=$1)',member.relation_name) INTO present USING p_scan;
        IF present THEN RAISE EXCEPTION 'ghost_merge_target_initial_analysis_requires_attention' USING ERRCODE='55000'; END IF;
    END LOOP;
    PERFORM internal.assert_initial_cancellation_transients_absent(p_scan);
    IF EXISTS(SELECT 1 FROM internal.initial_preparation_admission_staging WHERE scan_id=p_scan)
        OR EXISTS(SELECT 1 FROM internal.initial_preparation_admission_writes WHERE scan_id=p_scan)
        OR (SELECT count(*) FROM internal.ai_quota_reservations
            WHERE request_id=p_scan OR original_analysis_id=p_scan OR complimentary_client_scan_id=p_scan)<>1 THEN
        RAISE EXCEPTION 'ghost_merge_target_initial_analysis_requires_attention' USING ERRCODE='55000';
    END IF;
    SELECT * INTO q FROM internal.ai_quota_reservations WHERE user_id=p_owner AND request_id=p_scan;
    IF NOT FOUND OR q.original_analysis_id IS DISTINCT FROM p_scan
        OR q.operation NOT IN ('scan_identification','scan_audio_identification')
        OR q.state IS DISTINCT FROM 'refunded' OR q.refund_count<>1 OR q.attempt_count<>1 OR q.stale_recovery_count<>0
        OR q.committed_at IS NOT NULL OR q.failed_at IS NOT NULL OR q.refunded_at IS NULL
        OR NOT pg_catalog.isfinite(q.refunded_at) OR q.refunded_at<q.reserved_at OR q.updated_at IS DISTINCT FROM q.refunded_at
        OR (q.effective_plan='pro_complimentary') IS DISTINCT FROM (q.complimentary_client_scan_id IS NOT NULL)
        OR EXISTS(SELECT 1 FROM internal.ai_quota_reservation_counters WHERE reservation_id=q.id)
        OR (SELECT count(*) FROM internal.identification_provider_attempts WHERE reservation_id=q.id)<>1 THEN
        RAISE EXCEPTION 'ghost_merge_target_initial_analysis_requires_attention' USING ERRCODE='55000';
    END IF;
    SELECT * INTO attempt FROM internal.identification_provider_attempts WHERE reservation_id=q.id AND attempt_count=1;
    IF NOT FOUND OR attempt.operation IS DISTINCT FROM q.operation OR attempt.effective_plan IS DISTINCT FROM q.effective_plan
        OR attempt.model IS DISTINCT FROM q.model OR attempt.policy_version IS DISTINCT FROM q.policy_version
        OR attempt.created_at>q.refunded_at THEN
        RAISE EXCEPTION 'ghost_merge_target_initial_analysis_requires_attention' USING ERRCODE='55000';
    END IF;
    SELECT * INTO usage_row FROM internal.complimentary_scan_usage WHERE user_id=p_owner AND client_scan_id=p_scan;
    IF q.complimentary_client_scan_id IS NOT NULL THEN
        IF q.complimentary_client_scan_id IS DISTINCT FROM p_scan OR NOT FOUND
            OR usage_row.state IS DISTINCT FROM 'released' OR usage_row.settlement_reason IS DISTINCT FROM 'cancelled_before_dispatch'
            OR usage_row.settled_at IS NULL OR NOT pg_catalog.isfinite(usage_row.settled_at)
            OR usage_row.settled_at<usage_row.held_at OR usage_row.settled_at<q.refunded_at
            OR usage_row.updated_at IS DISTINCT FROM usage_row.settled_at THEN
            RAISE EXCEPTION 'ghost_merge_target_initial_analysis_requires_attention' USING ERRCODE='55000';
        END IF;
    ELSIF FOUND THEN
        RAISE EXCEPTION 'ghost_merge_target_initial_analysis_requires_attention' USING ERRCODE='55000';
    END IF;
    IF EXISTS(SELECT 1 FROM internal.identification_invocations WHERE scan_id=p_scan OR reservation_id=q.id)
        OR EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings WHERE analysis_id=p_scan)
        OR EXISTS(SELECT 1 FROM internal.observation_analysis_intents WHERE analysis_id=p_scan)
        OR EXISTS(SELECT 1 FROM internal.observation_analysis_results WHERE analysis_id=p_scan)
        OR EXISTS(SELECT 1 FROM public.scan_ingestion_intents WHERE internal.source_child_uuid(scan_id)=p_scan)
        OR EXISTS(SELECT 1 FROM public.scan_ingestion_jobs WHERE internal.source_child_uuid(scan_id)=p_scan)
        OR EXISTS(SELECT 1 FROM internal.complimentary_scan_usage WHERE user_id<>p_owner AND client_scan_id=p_scan)
        OR EXISTS(SELECT 1 FROM internal.ai_quota_reservations WHERE user_id=p_source
            AND (request_id=q.request_id OR original_analysis_id=p_scan OR complimentary_client_scan_id=p_scan)) THEN
        RAISE EXCEPTION 'ghost_merge_target_initial_analysis_requires_attention' USING ERRCODE='55000';
    END IF;
END;
$$;

CREATE FUNCTION internal.assert_ghost_target_initial_funding(p_source UUID,p_target UUID)
RETURNS VOID LANGUAGE PLPGSQL VOLATILE SECURITY INVOKER SET search_path='' AS $$
DECLARE scan UUID; scans UUID[]; member RECORD; present BOOLEAN;
BEGIN
    IF p_source IS NULL OR p_target IS NULL OR p_source=p_target THEN
        RAISE EXCEPTION 'ghost_merge_target_initial_analysis_requires_attention' USING ERRCODE='55000';
    END IF;
    IF current_setting('transaction_isolation')<>'read committed' THEN
        RAISE EXCEPTION 'initial_analysis_isolation_unavailable' USING ERRCODE='25000';
    END IF;
    -- The fixed merge owner already holds this same ordered pair; repeating
    -- here protects trusted direct use without acquiring an inner owner later.
    PERFORM id FROM public.users WHERE id IN(p_source,p_target) ORDER BY id FOR UPDATE;
    IF (SELECT count(*) FROM public.users WHERE id IN(p_source,p_target))<>2 THEN
        RAISE EXCEPTION 'ghost_merge_target_initial_analysis_requires_attention' USING ERRCODE='55000';
    END IF;
    SELECT COALESCE(array_agg(DISTINCT candidate ORDER BY candidate),'{}'::UUID[]) INTO scans
        FROM internal.initial_merge_target_admitted_scans(p_target) candidate;
    FOREACH scan IN ARRAY scans LOOP
        PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('merian-scan-ingestion:'||scan::TEXT,0::BIGINT));
    END LOOP;
    FOREACH scan IN ARRAY scans LOOP
        -- Active/unknown work cannot take a terminal exception or reach generic
        -- merge funding logic, even if the saved private proof is damaged.
        FOR member IN SELECT relation_name FROM internal.initial_cancellation_private_catalog() LOOP
            EXECUTE format('SELECT EXISTS(SELECT 1 FROM %s WHERE scan_id=$1)',member.relation_name) INTO present USING scan;
            IF present THEN RAISE EXCEPTION 'ghost_merge_target_initial_analysis_requires_attention' USING ERRCODE='55000'; END IF;
        END LOOP;
        PERFORM internal.lock_initial_merge_target_terminal(p_target,scan);
        PERFORM internal.assert_initial_merge_target_terminal(p_source,p_target,scan);
    END LOOP;
END;
$$;
REVOKE ALL ON FUNCTION internal.initial_merge_target_admitted_scans(UUID),
    internal.lock_initial_merge_target_terminal(UUID,UUID),
    internal.assert_initial_merge_target_terminal(UUID,UUID,UUID),
    internal.assert_ghost_target_initial_funding(UUID,UUID) FROM PUBLIC,anon,authenticated,service_role;

DO $merge_guard$
DECLARE definition TEXT; anchor TEXT := $anchor$    SELECT profile.*
    INTO STRICT ghost_profile$anchor$;
BEGIN
    SELECT pg_catalog.pg_get_functiondef('internal.perform_ghost_profile_merge(uuid,uuid)'::REGPROCEDURE) INTO STRICT definition;
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
        RAISE EXCEPTION 'initial admitted Ghost target guard seam drift';
    END IF;
    EXECUTE replace(definition,anchor,$replacement$    PERFORM internal.assert_ghost_target_initial_funding(p_ghost_user_id,p_target_user_id);

$replacement$||anchor);
END;
$merge_guard$;
