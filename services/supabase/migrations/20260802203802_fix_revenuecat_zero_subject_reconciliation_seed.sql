-- A synthetic reconciliation seed has no webhook subjects. The event ledger
-- constraint therefore requires the zero-count row to use the `ignored`
-- outcome. Preserve every other part of the installed, reviewed function.

SET lock_timeout = '5s';
SET statement_timeout = '30s';

DO $migration$
DECLARE
    function_sql TEXT;
    patched_sql TEXT;
    target_occurrences INTEGER;
    old_seed_values CONSTANT TEXT :=
E'                ''applied'',
                0,
                0,
                0';
    new_seed_values CONSTANT TEXT :=
E'                ''ignored'',
                0,
                0,
                0';
BEGIN
    SELECT pg_catalog.PG_GET_FUNCTIONDEF(
        pg_catalog.TO_REGPROCEDURE(
            'public.apply_revenuecat_reconciliation(uuid,uuid,bigint,text,timestamp with time zone)'
        )
    )
    INTO function_sql;

    IF function_sql IS NULL THEN
        RAISE EXCEPTION
            'apply_revenuecat_reconciliation is missing during seed repair';
    END IF;

    target_occurrences := (
        pg_catalog.LENGTH(function_sql)
        - pg_catalog.LENGTH(
            pg_catalog.REPLACE(function_sql, old_seed_values, '')
        )
    ) / pg_catalog.LENGTH(old_seed_values);

    IF target_occurrences <> 1 THEN
        RAISE EXCEPTION 'revenuecat_reconciliation_seed_source_drift'
            USING ERRCODE = '55000';
    END IF;

    patched_sql := pg_catalog.REPLACE(
        function_sql,
        old_seed_values,
        new_seed_values
    );

    IF pg_catalog.STRPOS(patched_sql, old_seed_values) > 0
       OR pg_catalog.STRPOS(patched_sql, new_seed_values) = 0 THEN
        RAISE EXCEPTION 'revenuecat_reconciliation_seed_patch_failed'
            USING ERRCODE = '55000';
    END IF;

    EXECUTE patched_sql;
END;
$migration$;

RESET statement_timeout;
RESET lock_timeout;
