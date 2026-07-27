-- Account deletion and ghost-profile merging update or delete parent user rows.
-- Every owned single-column user FK therefore needs a non-partial leading index
-- to avoid sequential scans and long-lived locks while enforcing the FK.
--
-- The catalog-driven form covers the effective production schema rather than
-- relying on a migration-text heuristic. Existing valid indexes are reused.

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '15min';

DO $migration$
DECLARE
    foreign_key RECORD;
    index_name TEXT;
    max_inline_relation_bytes CONSTANT BIGINT := 33554432;
BEGIN
    FOR foreign_key IN
        SELECT DISTINCT
            source_table.oid AS table_oid,
            source_table.relkind AS relation_kind,
            source_namespace.nspname AS schema_name,
            source_table.relname AS table_name,
            source_column.attname AS column_name
        FROM pg_catalog.pg_constraint AS constraint_row
        JOIN pg_catalog.pg_class AS source_table
          ON source_table.oid = constraint_row.conrelid
        JOIN pg_catalog.pg_namespace AS source_namespace
          ON source_namespace.oid = source_table.relnamespace
        JOIN pg_catalog.pg_attribute AS source_column
          ON source_column.attrelid = constraint_row.conrelid
         AND source_column.attnum = constraint_row.conkey[1]
        WHERE constraint_row.contype = 'f'
          AND constraint_row.confrelid IN (
              'public.users'::REGCLASS,
              'auth.users'::REGCLASS
          )
          AND source_namespace.nspname IN ('public', 'internal')
          AND source_table.relkind IN ('r', 'p')
          AND pg_catalog.ARRAY_LENGTH(constraint_row.conkey, 1) = 1
          AND NOT EXISTS (
              SELECT 1
              FROM pg_catalog.pg_index AS index_row
              WHERE index_row.indrelid = constraint_row.conrelid
                AND index_row.indisvalid
                AND index_row.indisready
                AND index_row.indpred IS NULL
                AND index_row.indexprs IS NULL
                AND index_row.indkey[0] = constraint_row.conkey[1]
          )
        ORDER BY
            source_namespace.nspname,
            source_table.relname,
            source_column.attname
    LOOP
        index_name := pg_catalog.FORMAT(
            'idx_%s_%s_%s_user_fk',
            pg_catalog.SUBSTRING(foreign_key.table_name FOR 24),
            pg_catalog.SUBSTRING(foreign_key.column_name FOR 16),
            pg_catalog.SUBSTRING(
                pg_catalog.MD5(
                    foreign_key.schema_name || '.'
                    || foreign_key.table_name || '.'
                    || foreign_key.column_name
                )
                FOR 8
            )
        );

        IF foreign_key.relation_kind = 'p' THEN
            RAISE EXCEPTION
                'Refusing a recursive blocking user-FK index build on partitioned table %.%.',
                foreign_key.schema_name,
                foreign_key.table_name
                USING
                    ERRCODE = '55000',
                    HINT =
                        'Build valid leading indexes concurrently on every leaf partition, create the parent partitioned index as a metadata-only operation, then retry.';
        END IF;

        IF pg_catalog.PG_RELATION_SIZE(foreign_key.table_oid)
            > max_inline_relation_bytes THEN
            RAISE EXCEPTION
                'Refusing a blocking user-FK index build on %.% (% bytes).',
                foreign_key.schema_name,
                foreign_key.table_name,
                pg_catalog.PG_RELATION_SIZE(foreign_key.table_oid)
                USING
                    ERRCODE = '55000',
                    HINT = pg_catalog.FORMAT(
                        'Run CREATE INDEX CONCURRENTLY %I ON %I.%I (%I) outside db push, verify indisvalid and indisready, then retry.',
                        index_name,
                        foreign_key.schema_name,
                        foreign_key.table_name,
                        foreign_key.column_name
                    );
        END IF;

        EXECUTE pg_catalog.FORMAT(
            'CREATE INDEX %I ON %I.%I (%I)',
            index_name,
            foreign_key.schema_name,
            foreign_key.table_name,
            foreign_key.column_name
        );
    END LOOP;
END;
$migration$;
