-- Local staging/acceptance is not proof that server work survives source Auth retirement.
-- Preserve the reviewed merge owner, privileges, and lock order; reject instead of
-- converting live guest ingestion into an interrupted destination retry.
SET lock_timeout = '5s';
SET statement_timeout = '30s';

-- Every supported entry that can admit/recover source work takes the same
-- profile lock and proves the owner still exists after waking. Auth-row FKs
-- alone do not serialize against retirement of the distinct public profile.
DO $owners$
DECLARE
    signature TEXT;
    definition TEXT;
    anchor TEXT := '    PERFORM internal.require_service_role();';
    fence TEXT := $fence$
    IF p_user_id IS NOT NULL THEN
        PERFORM id FROM public.users WHERE id = p_user_id FOR UPDATE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'scan_ingestion_owner_unavailable' USING ERRCODE = 'P0002';
        END IF;
    END IF;
$fence$;
BEGIN
    FOREACH signature IN ARRAY ARRAY[
        'public.begin_scan_ingestion(text,uuid,text,jsonb,jsonb,jsonb,text[],text,text,boolean,boolean,jsonb,integer,integer)',
        'public.claim_scan_ingestion_job(text,uuid,text,jsonb,jsonb,uuid[],text,integer)',
        'public.record_scan_ingestion_intent(text,uuid,text,jsonb,jsonb,jsonb,uuid[],text,text,boolean,boolean,jsonb,integer)',
        'public.recover_missing_owned_scan(uuid,uuid,jsonb)',
        'public.recover_inline_scan_ingestion_completion(uuid,uuid)',
        'public.recover_stranded_scan_ingestion_attempt(uuid,uuid)'
    ] LOOP
        SELECT pg_catalog.pg_get_functiondef(signature::pg_catalog.regprocedure) INTO STRICT definition;
        IF (pg_catalog.length(definition) - pg_catalog.length(pg_catalog.replace(definition, anchor, '')))
            / pg_catalog.length(anchor) <> 1 THEN
            RAISE EXCEPTION 'Reviewed source-work admission boundary changed: %', signature;
        END IF;
        EXECUTE pg_catalog.replace(definition, anchor, anchor || fence);
    END LOOP;
END;
$owners$;

DO $migration$
DECLARE
    definition TEXT;
    rewritten TEXT;
    anchor TEXT := '    PERFORM internal.prepare_scan_ingestions_for_identity_merge(';
    guard_sql TEXT := $guard$
    -- The source/destination public user locks are already held. Ingestion
    -- admission takes that same owner lock before inserting new source work.
    PERFORM job.scan_id
    FROM public.scan_ingestion_jobs AS job
    WHERE job.user_id = p_ghost_user_id
      AND job.status NOT IN ('complete', 'failed_terminal')
    FOR UPDATE;
    IF FOUND THEN
        RAISE EXCEPTION 'ghost_merge_source_work_pending' USING ERRCODE = '55000';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.scan_ingestion_intents AS intent
        WHERE intent.user_id = p_ghost_user_id
          AND intent.resumable
          AND NOT EXISTS (
              SELECT 1 FROM public.scan_ingestion_jobs AS job
              WHERE job.user_id = intent.user_id AND job.scan_id = intent.scan_id
                AND job.status IN ('complete', 'failed_terminal')
          )
    ) THEN
        RAISE EXCEPTION 'ghost_merge_source_work_pending' USING ERRCODE = '55000';
    END IF;

    -- The prepared history protocol uses explicit owner UUIDs without user FKs.
    -- Until its ownership-transfer contract is implemented, retaining any such
    -- source evidence is safer than deleting its owner and stranding the media.
    IF EXISTS (
        SELECT 1 FROM internal.observation_analysis_intents
        WHERE owner_id = p_ghost_user_id
    ) OR EXISTS (
        SELECT 1 FROM internal.observation_evidence_objects
        WHERE owner_id = p_ghost_user_id
    ) THEN
        RAISE EXCEPTION 'ghost_merge_source_history_requires_attention' USING ERRCODE = '55000';
    END IF;

$guard$;
BEGIN
    SELECT pg_catalog.pg_get_functiondef(
        'internal.perform_ghost_profile_merge(uuid,uuid)'::pg_catalog.regprocedure
    ) INTO STRICT definition;
    IF (pg_catalog.length(definition) - pg_catalog.length(pg_catalog.replace(definition, anchor, '')))
        / pg_catalog.length(anchor) <> 1 THEN
        RAISE EXCEPTION 'Expected exactly one reviewed identity merge scan boundary';
    END IF;
    rewritten := pg_catalog.replace(definition, anchor, guard_sql || anchor);
    EXECUTE rewritten;
END;
$migration$;

RESET statement_timeout;
RESET lock_timeout;
