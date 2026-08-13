-- The stable purchase-principal migration replaced two previously lint-clean
-- RevenueCat routines and reintroduced an explicit integer FOR-loop variable
-- plus an unread composite lock row. Rebuild only the installed definitions so
-- the reviewed bodies, lock order, security settings, ownership, comments, and
-- ACLs remain unchanged.

SET lock_timeout = '5s';
SET statement_timeout = '30s';

DO $migration$
DECLARE
    function_sql TEXT;
    patched_sql TEXT;
    declaration_occurrences INTEGER;
    subject_index_declaration CONSTANT TEXT :=
        E'    subject_index INTEGER;\n';
BEGIN
    SELECT pg_catalog.PG_GET_FUNCTIONDEF(
        pg_catalog.TO_REGPROCEDURE(
            'public.apply_revenuecat_identity_state(text,bigint,text,text,bigint,jsonb)'
        )
    )
    INTO function_sql;

    IF function_sql IS NULL THEN
        RAISE EXCEPTION
            'apply_revenuecat_identity_state is missing during lint repair';
    END IF;

    declaration_occurrences := (
        pg_catalog.CHAR_LENGTH(function_sql) -
        pg_catalog.CHAR_LENGTH(
            pg_catalog.REPLACE(
                function_sql,
                subject_index_declaration,
                ''
            )
        )
    ) / pg_catalog.CHAR_LENGTH(subject_index_declaration);
    IF declaration_occurrences <> 1 THEN
        RAISE EXCEPTION
            'apply_revenuecat_identity_state lint repair expected one reviewed declaration, found %',
            declaration_occurrences;
    END IF;

    patched_sql := pg_catalog.REPLACE(
        function_sql,
        subject_index_declaration,
        ''
    );

    IF patched_sql = function_sql
       OR patched_sql ~* E'\\msubject_index\\M[[:space:]]+integer[[:space:]]*;'
       OR pg_catalog.STRPOS(
            patched_sql,
            'FOR subject_index IN 1..subject_total LOOP'
          ) = 0 THEN
        RAISE EXCEPTION
            'apply_revenuecat_identity_state lint repair did not match the reviewed definition';
    END IF;

    EXECUTE patched_sql;
END;
$migration$;

DO $migration$
DECLARE
    function_sql TEXT;
    patched_sql TEXT;
    declaration_occurrences INTEGER;
    select_occurrences INTEGER;
    queue_row_declaration CONSTANT TEXT :=
        E'    queue_row internal.purchase_principal_reconciliation_queue%ROWTYPE;\n';
    lock_only_select CONSTANT TEXT :=
        E'    SELECT queue.*\n'
        '    INTO STRICT queue_row\n'
        '    FROM internal.purchase_principal_reconciliation_queue AS queue\n'
        '    WHERE queue.purchase_principal_id = principal.id\n'
        '      AND queue.claim_token = p_claim_token\n'
        '      AND queue.claim_expires_at > pg_catalog.CLOCK_TIMESTAMP()\n'
        '    FOR UPDATE;\n';
    lock_only_perform CONSTANT TEXT :=
        E'    PERFORM 1\n'
        '    FROM internal.purchase_principal_reconciliation_queue AS queue\n'
        '    WHERE queue.purchase_principal_id = principal.id\n'
        '      AND queue.claim_token = p_claim_token\n'
        '      AND queue.claim_expires_at > pg_catalog.CLOCK_TIMESTAMP()\n'
        '    FOR UPDATE;\n'
        '    IF NOT FOUND THEN\n'
        '        RAISE EXCEPTION ''purchase_principal_reconciliation_claim_lost''\n'
        '            USING ERRCODE = ''55000'';\n'
        '    END IF;\n';
BEGIN
    SELECT pg_catalog.PG_GET_FUNCTIONDEF(
        pg_catalog.TO_REGPROCEDURE(
            'public.apply_purchase_principal_reconciliation(uuid,uuid,bigint,text,timestamp with time zone,text,timestamp with time zone)'
        )
    )
    INTO function_sql;

    IF function_sql IS NULL THEN
        RAISE EXCEPTION
            'apply_purchase_principal_reconciliation is missing during lint repair';
    END IF;

    declaration_occurrences := (
        pg_catalog.CHAR_LENGTH(function_sql) -
        pg_catalog.CHAR_LENGTH(
            pg_catalog.REPLACE(function_sql, queue_row_declaration, '')
        )
    ) / pg_catalog.CHAR_LENGTH(queue_row_declaration);
    select_occurrences := (
        pg_catalog.CHAR_LENGTH(function_sql) -
        pg_catalog.CHAR_LENGTH(
            pg_catalog.REPLACE(function_sql, lock_only_select, '')
        )
    ) / pg_catalog.CHAR_LENGTH(lock_only_select);
    IF declaration_occurrences <> 1 OR select_occurrences <> 1 THEN
        RAISE EXCEPTION
            'apply_purchase_principal_reconciliation lint repair expected one declaration and one lock select, found % and %',
            declaration_occurrences,
            select_occurrences;
    END IF;

    patched_sql := pg_catalog.REPLACE(
        function_sql,
        queue_row_declaration,
        ''
    );
    patched_sql := pg_catalog.REPLACE(
        patched_sql,
        lock_only_select,
        lock_only_perform
    );

    IF patched_sql = function_sql
       OR pg_catalog.STRPOS(patched_sql, 'queue_row') > 0
       OR pg_catalog.STRPOS(patched_sql, lock_only_perform) = 0 THEN
        RAISE EXCEPTION
            'apply_purchase_principal_reconciliation lint repair did not match the reviewed definition';
    END IF;

    EXECUTE patched_sql;
END;
$migration$;

RESET statement_timeout;
RESET lock_timeout;
