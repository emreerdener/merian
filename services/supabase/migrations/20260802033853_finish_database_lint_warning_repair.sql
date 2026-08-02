-- Finish the warning cleanup exposed by the strict disposable-database lint
-- gate. Keep every published RPC signature and existing ACL intact while
-- rebuilding only the reviewed PL/pgSQL definitions.

DO $migration$
DECLARE
    function_sql TEXT;
    patched_sql TEXT;
BEGIN
    SELECT pg_catalog.PG_GET_FUNCTIONDEF(
        pg_catalog.TO_REGPROCEDURE(
            'public.authorize_species_observation_stats_request(uuid,text,uuid)'
        )
    )
    INTO function_sql;

    IF function_sql IS NULL THEN
        RAISE EXCEPTION
            'authorize_species_observation_stats_request is missing during lint repair';
    END IF;

    patched_sql := pg_catalog.REPLACE(
        function_sql,
        E'    ignored_count INTEGER;\n',
        ''
    );
    patched_sql := pg_catalog.REPLACE(
        patched_sql,
        'ignored_count := internal.consume_species_observation_stats_rate(',
        'PERFORM internal.consume_species_observation_stats_rate('
    );

    IF patched_sql = function_sql
       OR pg_catalog.STRPOS(patched_sql, 'ignored_count') > 0 THEN
        RAISE EXCEPTION
            'authorize_species_observation_stats_request lint repair did not match the reviewed definition';
    END IF;

    EXECUTE patched_sql;
END;
$migration$;

DO $migration$
DECLARE
    function_sql TEXT;
    patched_sql TEXT;
BEGIN
    SELECT pg_catalog.PG_GET_FUNCTIONDEF(
        pg_catalog.TO_REGPROCEDURE(
            'public.claim_species_observation_stats_population(uuid,uuid,text)'
        )
    )
    INTO function_sql;

    IF function_sql IS NULL THEN
        RAISE EXCEPTION
            'claim_species_observation_stats_population is missing during lint repair';
    END IF;

    patched_sql := pg_catalog.REPLACE(
        function_sql,
        E'    ignored_count INTEGER;\n',
        ''
    );
    patched_sql := pg_catalog.REPLACE(
        patched_sql,
        'ignored_count := internal.consume_species_observation_stats_rate(',
        'PERFORM internal.consume_species_observation_stats_rate('
    );

    IF patched_sql = function_sql
       OR pg_catalog.STRPOS(patched_sql, 'ignored_count') > 0 THEN
        RAISE EXCEPTION
            'claim_species_observation_stats_population lint repair did not match the reviewed definition';
    END IF;

    EXECUTE patched_sql;
END;
$migration$;

DO $migration$
DECLARE
    function_sql TEXT;
    patched_sql TEXT;
BEGIN
    SELECT pg_catalog.PG_GET_FUNCTIONDEF(
        pg_catalog.TO_REGPROCEDURE(
            'public.begin_scan_ingestion(text,uuid,text,jsonb,jsonb,jsonb,text[],text,text,boolean,boolean,jsonb,integer,integer)'
        )
    )
    INTO function_sql;

    IF function_sql IS NULL THEN
        RAISE EXCEPTION
            'begin_scan_ingestion is missing during lint repair';
    END IF;

    -- These deprecated checksum arguments remain in the RPC for compatibility.
    -- The routine intentionally recomputes both checksums from canonical data;
    -- explicitly consuming the inputs documents that contract for the checker.
    patched_sql := pg_catalog.REPLACE(
        function_sql,
        E'BEGIN\n    PERFORM internal.require_service_role();\n',
        E'BEGIN\n    PERFORM internal.require_service_role();\n\n    -- Compatibility-only inputs are ignored in favor of canonical checksums.\n    PERFORM p_manifest_checksum, p_payload_checksum;\n'
    );

    IF patched_sql = function_sql
       OR pg_catalog.STRPOS(
            patched_sql,
            'PERFORM p_manifest_checksum, p_payload_checksum;'
       ) = 0 THEN
        RAISE EXCEPTION
            'begin_scan_ingestion lint repair did not match the reviewed definition';
    END IF;

    EXECUTE patched_sql;
END;
$migration$;

DO $migration$
DECLARE
    function_sql TEXT;
    patched_sql TEXT;
BEGIN
    SELECT pg_catalog.PG_GET_FUNCTIONDEF(
        pg_catalog.TO_REGPROCEDURE(
            'internal.materialize_dwca_export_source_snapshot(uuid)'
        )
    )
    INTO function_sql;

    IF function_sql IS NULL THEN
        RAISE EXCEPTION
            'materialize_dwca_export_source_snapshot is missing during lint repair';
    END IF;

    patched_sql := pg_catalog.REPLACE(
        function_sql,
        'source_cursor REFCURSOR := ''dwca_export_snapshot_cursor'';',
        'source_cursor REFCURSOR := ''dwca_export_snapshot_cursor''::REFCURSOR;'
    );

    IF patched_sql = function_sql
       OR pg_catalog.STRPOS(
            patched_sql,
            '''dwca_export_snapshot_cursor''::REFCURSOR'
       ) = 0 THEN
        RAISE EXCEPTION
            'materialize_dwca_export_source_snapshot lint repair did not match the reviewed definition';
    END IF;

    EXECUTE patched_sql;
END;
$migration$;

-- TO_JSONB(anyelement) is STABLE because it can depend on a type's output
-- function. This predicate uses TO_JSONB for composite-ledger comparisons and
-- therefore cannot promise IMMUTABLE volatility.
ALTER FUNCTION internal.inline_scan_recovery_ledger_matches(
    public.scan_ingestion_jobs,
    public.scan_ingestion_intents,
    UUID,
    TEXT[],
    TEXT[]
) STABLE;
