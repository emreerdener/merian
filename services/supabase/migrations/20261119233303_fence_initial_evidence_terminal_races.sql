SET lock_timeout = '5s';
SET statement_timeout = '2min';

DO $$
DECLARE definition TEXT; anchor TEXT;
BEGIN
    -- A legacy admitted identity cannot be reinterpreted as a new evidence
    -- request. This also prevents a concurrent legacy claimant from racing an
    -- in-place upgrade that was invisible to its candidate snapshot.
    SELECT pg_catalog.pg_get_functiondef('internal.bind_ordinary_initial_intent()'::REGPROCEDURE)
        INTO STRICT definition;
    anchor := E'BEGIN\n';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor) <> 1 THEN
        RAISE EXCEPTION 'Reviewed initial intent binding changed';
    END IF;
    EXECUTE replace(definition,anchor,anchor||$guard$
    IF TG_OP='UPDATE' AND NOT (OLD.request_payload ? 'initialEvidence')
        AND NEW.request_payload ? 'initialEvidence' THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
$guard$);

    -- Candidate filtering is not authorization for an old decision to settle
    -- funding. Recheck under the same user -> job locks as terminalization,
    -- after any in-flight intent binding has committed or rolled back.
    SELECT pg_catalog.pg_get_functiondef('public.fail_scan_ingestion_terminal(uuid,uuid,text,text,text)'::REGPROCEDURE)
        INTO STRICT definition;
    anchor := E'    PERFORM pg_catalog.SET_CONFIG(\n        ''merian.complimentary_terminal_fence'',';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor) <> 1 THEN
        RAISE EXCEPTION 'Reviewed initial terminal settlement boundary changed';
    END IF;
    EXECUTE replace(definition,anchor,$guard$
    IF p_terminal_reason_code IN ('replay_exhausted','media_reconciliation_abandoned') THEN
        PERFORM jobs.id FROM public.scan_ingestion_jobs jobs
            WHERE jobs.scan_id=p_scan_id::TEXT AND jobs.user_id=p_user_id FOR UPDATE;
        IF EXISTS(SELECT 1 FROM public.scan_ingestion_jobs jobs
                WHERE jobs.scan_id=p_scan_id::TEXT AND jobs.user_id=p_user_id
                    AND jobs.initial_evidence_generation IS NOT NULL)
            OR EXISTS(SELECT 1 FROM public.scan_ingestion_intents intents
                WHERE intents.scan_id=p_scan_id::TEXT AND intents.user_id=p_user_id
                    AND intents.request_payload ? 'initialEvidence')
            OR EXISTS(SELECT 1 FROM internal.ordinary_initial_evidence evidence
                WHERE evidence.scan_id=p_scan_id) THEN
            RAISE EXCEPTION 'initial_evidence_recovery_required' USING ERRCODE='55000';
        END IF;
    END IF;
$guard$||anchor);
END;
$$;

RESET statement_timeout;
RESET lock_timeout;
