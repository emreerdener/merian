\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(1);
DO $test$
DECLARE role_name TEXT;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_class
        WHERE oid = 'internal.dwca_export_snapshot_source'::REGCLASS
          AND relkind = 'v' AND reloptions @> ARRAY['security_invoker=true']
    ) THEN RAISE EXCEPTION 'export snapshot source lost invoker rights'; END IF;
    FOREACH role_name IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
        IF pg_catalog.HAS_TABLE_PRIVILEGE(role_name, 'internal.dwca_export_snapshot_source', 'SELECT') THEN
            RAISE EXCEPTION 'export source view exposed to API role';
        END IF;
    END LOOP;
    IF pg_catalog.STRPOS(
        pg_catalog.PG_GET_VIEWDEF('internal.dwca_export_snapshot_source'::REGCLASS, TRUE),
        'identification_metrics_are_gemini_compatible') = 0 THEN
        RAISE EXCEPTION 'export snapshots do not freeze metric qualification';
    END IF;
END;
$test$;
SELECT extensions.pass('export metric qualification remains private and creation-time');
SELECT * FROM extensions.finish();
ROLLBACK;
