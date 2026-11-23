BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(10);

SELECT extensions.is(
    (length(definition)-length(replace(definition,fragment,'')))/length(fragment),
    2,
    'both legacy claim and exhaustion exclude initial evidence intents'
) FROM (SELECT pg_catalog.pg_get_functiondef('public.claim_replayable_scan_ingestion_jobs(integer,integer)'::REGPROCEDURE) definition,
    'NOT (intents.request_payload ? ''initialEvidence'')' fragment) source;
SELECT extensions.is(
    (length(definition)-length(replace(definition,fragment,'')))/length(fragment),
    2,
    'both branches preserve retained identities independently of intent contents'
) FROM (SELECT pg_catalog.pg_get_functiondef('public.claim_replayable_scan_ingestion_jobs(integer,integer)'::REGPROCEDURE) definition,
    'FROM internal.ordinary_initial_evidence initial_evidence' fragment) source;
SELECT extensions.ok(NOT has_function_privilege(role_name,'public.claim_replayable_scan_ingestion_jobs(integer,integer)','EXECUTE'),
    role_name||' cannot claim replay jobs') FROM unnest(ARRAY['anon','authenticated']) role_name;
SELECT extensions.ok(has_function_privilege('service_role','public.claim_replayable_scan_ingestion_jobs(integer,integer)','EXECUTE'),
    'service worker grant retained');
SELECT extensions.ok(prosecdef,'definer boundary retained') FROM pg_catalog.pg_proc
    WHERE oid='public.claim_replayable_scan_ingestion_jobs(integer,integer)'::REGPROCEDURE;
SELECT extensions.ok(proconfig @> ARRAY['search_path=""','statement_timeout=15s'],
    'empty search path and bounded statement retained') FROM pg_catalog.pg_proc
    WHERE oid='public.claim_replayable_scan_ingestion_jobs(integer,integer)'::REGPROCEDURE;
SELECT extensions.is(ordinary_initial_evidence_enabled,FALSE,'initial evidence activation remains closed')
    FROM internal.observation_history_rollout;
SELECT extensions.ok(position('initial_evidence_recovery_required' in pg_catalog.pg_get_functiondef(
    'public.fail_scan_ingestion_terminal(uuid,uuid,text,text,text)'::REGPROCEDURE)) > 0,
    'terminal settlement independently denies stale legacy recovery decisions');
SELECT extensions.ok(position('NOT (OLD.request_payload ? ''initialEvidence'')' in pg_catalog.pg_get_functiondef(
    'internal.bind_ordinary_initial_intent()'::REGPROCEDURE)) > 0,
    'legacy intent identities cannot be upgraded in place');
SELECT * FROM extensions.finish();
ROLLBACK;
