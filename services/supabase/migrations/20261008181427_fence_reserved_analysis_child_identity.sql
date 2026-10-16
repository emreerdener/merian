SET lock_timeout='5s';
SET statement_timeout='2min';

-- Legacy TEXT identifiers retain their original spelling and replay behavior.
-- Only their identity comparison uses PostgreSQL's accepted UUID forms.
CREATE FUNCTION internal.source_child_uuid(value TEXT)
RETURNS UUID LANGUAGE PLPGSQL IMMUTABLE STRICT SECURITY INVOKER SET search_path='' AS $$
BEGIN
    RETURN value::UUID;
EXCEPTION WHEN invalid_text_representation THEN RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION internal.source_child_uuid(TEXT) FROM PUBLIC,anon,authenticated,service_role;
CREATE INDEX source_binding_ingestion_intent_uuid ON public.scan_ingestion_intents(internal.source_child_uuid(scan_id))
    WHERE internal.source_child_uuid(scan_id) IS NOT NULL;
CREATE INDEX source_binding_ingestion_job_uuid ON public.scan_ingestion_jobs(internal.source_child_uuid(scan_id))
    WHERE internal.source_child_uuid(scan_id) IS NOT NULL;

-- A trigger must lock the owner before the child, including trusted raw INSERTs:
-- otherwise its later owner FK check can deadlock with a binding's owner lock.
-- Generic writers never acquire the parent or source locks.
CREATE FUNCTION internal.guard_source_child_ingestion()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
DECLARE child UUID;
BEGIN
    IF TG_TABLE_NAME='scans' THEN
        child:=NEW.id;
        IF TG_OP='UPDATE' AND NEW.id IS NOT DISTINCT FROM OLD.id THEN RETURN NEW; END IF;
    ELSE
        child:=internal.source_child_uuid(NEW.scan_id);
        IF TG_OP='UPDATE' AND NEW.scan_id IS NOT DISTINCT FROM OLD.scan_id
            AND NEW.user_id IS NOT DISTINCT FROM OLD.user_id THEN RETURN NEW; END IF;
    END IF;
    IF child IS NULL THEN RETURN NEW; END IF;
    -- Post-lock lookups require a fresh statement snapshot. A frozen transaction
    -- snapshot cannot establish absence after another transaction commits.
    IF current_setting('transaction_isolation') NOT IN ('read committed','read uncommitted') THEN
        RAISE EXCEPTION 'analysis_history_current_snapshot_required' USING ERRCODE='25000';
    END IF;
    PERFORM id FROM public.users WHERE id=NEW.user_id FOR KEY SHARE;
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
        'merian-scan-ingestion:' || child::TEXT,0::BIGINT));
    IF EXISTS(SELECT 1 FROM internal.observation_analysis_source_bindings WHERE analysis_id=child) THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='22023';
    END IF;
    RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION internal.guard_source_child_ingestion() FROM PUBLIC,anon,authenticated,service_role;
-- Owner-only scan updates (including deletion) do not acquire a late child lock.
CREATE TRIGGER b_guard_source_child_ingestion BEFORE INSERT OR UPDATE OF id
    ON public.scans FOR EACH ROW EXECUTE FUNCTION internal.guard_source_child_ingestion();
CREATE TRIGGER b_guard_source_child_ingestion BEFORE INSERT OR UPDATE OF scan_id,user_id
    ON public.scan_ingestion_jobs FOR EACH ROW EXECUTE FUNCTION internal.guard_source_child_ingestion();
CREATE TRIGGER b_guard_source_child_ingestion BEFORE INSERT OR UPDATE OF scan_id,user_id
    ON public.scan_ingestion_intents FOR EACH ROW EXECUTE FUNCTION internal.guard_source_child_ingestion();

DO $patch$
DECLARE definition TEXT; anchor TEXT;
BEGIN
    SELECT pg_catalog.pg_get_functiondef('internal.guard_observation_source_storage()'::REGPROCEDURE) INTO STRICT definition;
    anchor:='    IF NOT EXISTS(SELECT 1 FROM internal.observation_analysis_results';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>1 THEN
        RAISE EXCEPTION 'Reviewed source storage lock boundary changed';
    END IF;
    EXECUTE replace(definition,anchor,$body$
    IF current_setting('transaction_isolation') NOT IN ('read committed','read uncommitted') THEN
        RAISE EXCEPTION 'analysis_history_current_snapshot_required' USING ERRCODE='25000';
    END IF;
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
        'merian-scan-ingestion:' || NEW.analysis_id::TEXT,0::BIGINT));
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
        'merian-history-evidence:' || NEW.analysis_id::TEXT,0::BIGINT));
$body$ || anchor);
    SELECT pg_catalog.pg_get_functiondef('internal.validate_observation_source_binding()'::REGPROCEDURE) INTO STRICT definition;
    anchor:='WHERE scan_id=NEW.analysis_id::TEXT';
    IF (length(definition)-length(replace(definition,anchor,'')))/length(anchor)<>2 THEN
        RAISE EXCEPTION 'Reviewed source storage ingestion checks changed';
    END IF;
    EXECUTE replace(definition,anchor,'WHERE internal.source_child_uuid(scan_id)=NEW.analysis_id');
END;
$patch$;
-- This is an ingestion prerequisite only. Funding, media, intent and execution
-- writers still require coordinated cutover before any reservation RPC opens.
RESET statement_timeout;
RESET lock_timeout;
