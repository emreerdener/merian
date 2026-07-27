\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(1);

DO $test$
DECLARE
    missing_user_fk_index TEXT;
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_class AS relation_row
        JOIN pg_catalog.pg_namespace AS namespace_row
          ON namespace_row.oid = relation_row.relnamespace
        WHERE namespace_row.nspname = 'public'
          AND relation_row.relkind IN ('r', 'p')
          AND NOT relation_row.relrowsecurity
          AND NOT EXISTS (
              SELECT 1
              FROM pg_catalog.pg_depend AS dependency_row
              WHERE dependency_row.classid = 'pg_catalog.pg_class'::REGCLASS
                AND dependency_row.objid = relation_row.oid
                AND dependency_row.deptype = 'e'
          )
    ) THEN
        RAISE EXCEPTION 'an application table in public lacks RLS';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM (
            VALUES ('anon'), ('authenticated')
        ) AS api_role(role_name)
        CROSS JOIN (
            VALUES
                ('SELECT'),
                ('INSERT'),
                ('UPDATE'),
                ('DELETE'),
                ('TRUNCATE'),
                ('REFERENCES'),
                ('TRIGGER'),
                ('MAINTAIN')
        ) AS privilege_row(privilege_name)
        WHERE pg_catalog.HAS_TABLE_PRIVILEGE(
            api_role.role_name,
            'public.explore_comment_reactions',
            privilege_row.privilege_name
        )
    ) THEN
        RAISE EXCEPTION
            'an unprivileged API role can access comment reactions directly';
    END IF;

    IF NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.explore_comment_reactions',
        'SELECT'
    ) OR NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.explore_comment_reactions',
        'INSERT'
    ) OR NOT pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.explore_comment_reactions',
        'DELETE'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.explore_comment_reactions',
        'UPDATE'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.explore_comment_reactions',
        'TRUNCATE'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.explore_comment_reactions',
        'REFERENCES'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.explore_comment_reactions',
        'TRIGGER'
    ) OR pg_catalog.HAS_TABLE_PRIVILEGE(
        'service_role',
        'public.explore_comment_reactions',
        'MAINTAIN'
    ) THEN
        RAISE EXCEPTION 'comment reaction service-role ACL is not least privilege';
    END IF;

    SELECT pg_catalog.FORMAT(
        '%I.%I(%I)',
        source_namespace.nspname,
        source_table.relname,
        source_column.attname
    )
    INTO missing_user_fk_index
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
    LIMIT 1;

    IF missing_user_fk_index IS NOT NULL THEN
        RAISE EXCEPTION
            'user foreign key lacks a leading index: %',
            missing_user_fk_index;
    END IF;

    CREATE TABLE public.public_table_default_acl_probe (
        id UUID PRIMARY KEY
    );
    CREATE SEQUENCE public.public_sequence_default_acl_probe;

    IF EXISTS (
        SELECT 1
        FROM (
            VALUES ('anon'), ('authenticated'), ('service_role')
        ) AS api_role(role_name)
        CROSS JOIN (
            VALUES
                ('SELECT'),
                ('INSERT'),
                ('UPDATE'),
                ('DELETE'),
                ('TRUNCATE'),
                ('REFERENCES'),
                ('TRIGGER'),
                ('MAINTAIN')
        ) AS privilege_row(privilege_name)
        WHERE pg_catalog.HAS_TABLE_PRIVILEGE(
            api_role.role_name,
            'public.public_table_default_acl_probe',
            privilege_row.privilege_name
        )
    ) OR EXISTS (
        SELECT 1
        FROM (
            VALUES ('anon'), ('authenticated'), ('service_role')
        ) AS api_role(role_name)
        CROSS JOIN (
            VALUES ('USAGE'), ('SELECT'), ('UPDATE')
        ) AS privilege_row(privilege_name)
        WHERE pg_catalog.HAS_SEQUENCE_PRIVILEGE(
            api_role.role_name,
            'public.public_sequence_default_acl_probe',
            privilege_row.privilege_name
        )
    ) THEN
        RAISE EXCEPTION 'new public objects inherit an API-role privilege';
    END IF;

    DROP TABLE public.public_table_default_acl_probe;
    DROP SEQUENCE public.public_sequence_default_acl_probe;
END;
$test$;

SELECT extensions.pass(
    'public tables, API grants, defaults, and user FK indexes are secure'
);

ROLLBACK;
