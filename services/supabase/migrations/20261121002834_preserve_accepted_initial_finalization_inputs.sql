SET lock_timeout='5s';
SET statement_timeout='2min';

-- Pruning an operational row is not authority to erase an accepted, unfinished
-- result. Keep the original job ID, intent and provider/funding state in place.
-- Explicit terminal retirement, tombstones and account erasure keep their
-- existing owners. This guard neither revives retired evidence nor restores a
-- missing job from incomplete history.
CREATE FUNCTION internal.preserve_accepted_initial_finalization_inputs()
RETURNS TRIGGER LANGUAGE PLPGSQL SECURITY DEFINER SET search_path='' AS $$
BEGIN
    IF TG_OP<>'DELETE' OR TG_TABLE_SCHEMA<>'public'
        OR TG_TABLE_NAME NOT IN ('scan_ingestion_jobs','scan_ingestion_intents') THEN
        RAISE EXCEPTION 'analysis_history_operation_conflict' USING ERRCODE='55000';
    END IF;
    -- Row DELETE already owns the operational row lock. Do not acquire owner
    -- or evidence locks here in reverse order. Acceptance binds under the
    -- existing user -> scan -> evidence -> job/intent transaction fences.
    IF EXISTS(SELECT 1 FROM public.users WHERE id=OLD.user_id)
        AND EXISTS(SELECT 1 FROM auth.users WHERE id=OLD.user_id)
        AND NOT EXISTS(SELECT 1 FROM internal.account_deletion_jobs WHERE user_id=OLD.user_id)
        AND NOT EXISTS(SELECT 1 FROM internal.scan_deletion_tombstones WHERE scan_id::TEXT=OLD.scan_id)
        AND EXISTS(SELECT 1 FROM internal.ordinary_initial_evidence
            WHERE scan_id::TEXT=OLD.scan_id AND owner_id=OLD.user_id
            AND accepted_result IS NOT NULL AND sealed_at IS NULL AND retired_at IS NULL) THEN
        -- Returning NULL skips only this row in a pruning batch; other eligible
        -- rows still delete and their actual affected-row count remains truthful.
        RETURN NULL;
    END IF;
    RETURN OLD;
END;
$$;
REVOKE ALL ON FUNCTION internal.preserve_accepted_initial_finalization_inputs()
    FROM PUBLIC,anon,authenticated,service_role;
-- Must run before guard_ordinary_initial_job, which owns terminal erasure.
CREATE TRIGGER a_preserve_accepted_initial_finalization BEFORE DELETE ON public.scan_ingestion_jobs
    FOR EACH ROW EXECUTE FUNCTION internal.preserve_accepted_initial_finalization_inputs();
CREATE TRIGGER a_preserve_accepted_initial_finalization BEFORE DELETE ON public.scan_ingestion_intents
    FOR EACH ROW EXECUTE FUNCTION internal.preserve_accepted_initial_finalization_inputs();

RESET statement_timeout;
RESET lock_timeout;
