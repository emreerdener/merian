\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(1);

DO $test$
DECLARE
    api_role TEXT;
    target_signature TEXT;
BEGIN
    FOREACH target_signature IN ARRAY ARRAY[
        'public.field_trip_scan_evidence_is_eligible(public.scans)',
        'public.apply_field_trip_scan_progress_v2(uuid,uuid,uuid,uuid)',
        'public.apply_field_trip_challenge_scan_progress(uuid,uuid)'
    ] LOOP
        IF NOT EXISTS (
            SELECT 1 FROM pg_catalog.pg_proc AS p
            WHERE p.oid = pg_catalog.TO_REGPROCEDURE(target_signature)
              AND NOT p.prosecdef AND p.proconfig @> ARRAY['search_path=""']::TEXT[]
        ) THEN
            RAISE EXCEPTION 'Subject eligibility routine is missing or not a hardened invoker';
        END IF;
        FOREACH api_role IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
            IF pg_catalog.HAS_FUNCTION_PRIVILEGE(api_role, target_signature, 'EXECUTE') THEN
                RAISE EXCEPTION 'An API role can bypass the atomic Field Trip boundary';
            END IF;
        END LOOP;
    END LOOP;
    IF NOT pg_catalog.HAS_FUNCTION_PRIVILEGE('service_role', 'public.apply_field_trip_scan_progress_atomic(uuid,uuid,uuid,uuid)', 'EXECUTE')
       OR pg_catalog.HAS_FUNCTION_PRIVILEGE('authenticated', 'public.apply_field_trip_scan_progress_atomic(uuid,uuid,uuid,uuid)', 'EXECUTE')
       OR pg_catalog.HAS_FUNCTION_PRIVILEGE('anon', 'public.apply_field_trip_scan_progress_atomic(uuid,uuid,uuid,uuid)', 'EXECUTE') THEN
        RAISE EXCEPTION 'Atomic Field Trip service-only ACL changed';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_trigger AS t
        JOIN pg_catalog.pg_attribute AS a ON a.attrelid = t.tgrelid AND a.attnum = ANY(t.tgattr)
        WHERE t.tgrelid = 'public.scans'::REGCLASS
          AND t.tgname = 'trg_apply_ingested_scan_field_trip_progress_update'
          AND t.tgenabled = 'O' AND a.attname = 'user_identification_override'
    ) THEN
        RAISE EXCEPTION 'Human override does not invalidate Field Trip credit';
    END IF;
END;
$test$;
SELECT extensions.pass('Subject eligibility is private, atomic service access is preserved, and override edits enter reconciliation');
SELECT * FROM extensions.finish();
ROLLBACK;
