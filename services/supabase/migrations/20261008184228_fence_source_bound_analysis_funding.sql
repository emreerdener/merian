SET lock_timeout='5s';
SET statement_timeout='2min';

-- Deny-only preparation: source-aware admission will require its own exact
-- binding proof before any exception is introduced. request_id is deliberately
-- not a child identity; provider subcalls may use distinct idempotency UUIDs.
DO $patch$
DECLARE definition TEXT; anchor TEXT;
BEGIN
    SELECT pg_catalog.pg_get_functiondef('internal.reserve_ai_quota_core(uuid,text,uuid,text,uuid,boolean,integer,boolean)'::REGPROCEDURE) INTO STRICT definition;
    anchor:='        IF EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id=p_original_analysis_id)';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
        RAISE EXCEPTION 'Reviewed quota child lock boundary changed';
    END IF;
    EXECUTE replace(definition,anchor,$body$
        IF current_setting('transaction_isolation') NOT IN ('read committed','read uncommitted') THEN
            RAISE EXCEPTION 'analysis_history_current_snapshot_required' USING ERRCODE='25000';
        END IF;
        IF EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings WHERE analysis_id=p_original_analysis_id) THEN
            RAISE EXCEPTION 'analysis_history_admission_required' USING ERRCODE='55000';
        END IF;
$body$ || anchor);

    SELECT pg_catalog.pg_get_functiondef('public.commit_identification_invocation(uuid,uuid,uuid,integer,jsonb)'::REGPROCEDURE) INTO STRICT definition;
    -- Existing exact invocation replay remains before this fresh-dispatch fence.
    anchor:='    IF reserved.state <> ''reserved'' THEN';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
        RAISE EXCEPTION 'Reviewed invocation replay boundary changed';
    END IF;
    EXECUTE replace(definition,anchor,$body$
    IF current_setting('transaction_isolation') NOT IN ('read committed','read uncommitted') THEN
        RAISE EXCEPTION 'analysis_history_current_snapshot_required' USING ERRCODE='25000';
    END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
        'merian-scan-ingestion:' || reserved.original_analysis_id::TEXT,0::BIGINT));
    IF EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings WHERE analysis_id=reserved.original_analysis_id) THEN
        RAISE EXCEPTION 'analysis_history_dispatch_required' USING ERRCODE='55000';
    END IF;
$body$ || anchor);
END;
$patch$;
RESET statement_timeout;
RESET lock_timeout;
