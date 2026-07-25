-- Replace the synthetic all-zero owner with the relationally valid state:
-- retained observations are tombstoned and have no owner. This migration is
-- deliberately idempotent at every schema boundary because some preview/local
-- databases may have applied the superseded sentinel seed while production
-- rejected it before recording the migration.
BEGIN;

SET LOCAL lock_timeout = '10s';
SET LOCAL statement_timeout = '2min';

-- Auth signup/delete reaches public.users from auth.users, while scan writes
-- reach public.users from scans through the species-count statement trigger.
-- Lock Auth first, then preserve the scan-before-public-user order to avoid
-- taking the referenced Auth lock only after blocking profile writes.
LOCK TABLE auth.users IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public.scans IN SHARE ROW EXCLUSIVE MODE;
LOCK TABLE public.users IN SHARE ROW EXCLUSIVE MODE;

DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM auth.users AS auth_user
        WHERE auth_user.id =
            '00000000-0000-0000-0000-000000000000'::UUID
    ) THEN
        RAISE EXCEPTION 'legacy_auth_sentinel_requires_operator_removal'
            USING ERRCODE = '55000';
    END IF;
END;
$$;

ALTER TABLE public.scans
    ALTER COLUMN user_id DROP NOT NULL;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_catalog.pg_constraint AS constraint_row
        WHERE constraint_row.conrelid = 'public.scans'::REGCLASS
          AND constraint_row.conname =
              'scans_ownerless_requires_tombstone_check'
    ) THEN
        ALTER TABLE public.scans
            ADD CONSTRAINT scans_ownerless_requires_tombstone_check
            CHECK (user_id IS NOT NULL OR is_tombstoned)
            NOT VALID;
    END IF;
END;
$$;

-- Converge environments where the superseded migration created the sentinel.
-- Exact coordinates and free-form intervention notes are personal data and
-- have no retained biological-data purpose after ownership is erased.
UPDATE public.scans AS scans
SET user_id = NULL,
    is_tombstoned = TRUE,
    gps_lat_exact = NULL,
    gps_long_exact = NULL,
    gps_elevation = NULL,
    human_intervention_notes = NULL
WHERE scans.user_id =
    '00000000-0000-0000-0000-000000000000'::UUID;

ALTER TABLE public.scans
    VALIDATE CONSTRAINT scans_ownerless_requires_tombstone_check;

COMMENT ON CONSTRAINT scans_ownerless_requires_tombstone_check
    ON public.scans IS
    'Only a tombstoned observation may be retained without an owning user.';

-- Remove a legacy public-only sentinel if a local/preview database accepted it.
-- No auth.users row is created or modified.
DELETE FROM public.users AS users
WHERE users.id =
    '00000000-0000-0000-0000-000000000000'::UUID;

-- The production schema already has this canonical relationship, while the
-- migration history did not. Normalize it as RESTRICT so an Auth Admin call
-- cannot bypass relational cleanup, and declare it on fresh/local databases so
-- CI exercises the production invariant.
DO $$
DECLARE
    auth_fk RECORD;
    has_restrict_fk BOOLEAN := FALSE;
BEGIN
    FOR auth_fk IN
        SELECT
            constraint_row.conname,
            constraint_row.confdeltype
        FROM pg_catalog.pg_constraint AS constraint_row
        JOIN pg_catalog.pg_attribute AS source_column
          ON source_column.attrelid = constraint_row.conrelid
         AND source_column.attnum = constraint_row.conkey[1]
        JOIN pg_catalog.pg_attribute AS target_column
          ON target_column.attrelid = constraint_row.confrelid
         AND target_column.attnum = constraint_row.confkey[1]
        WHERE constraint_row.contype = 'f'
          AND constraint_row.conrelid = 'public.users'::REGCLASS
          AND constraint_row.confrelid = 'auth.users'::REGCLASS
          AND pg_catalog.ARRAY_LENGTH(constraint_row.conkey, 1) = 1
          AND pg_catalog.ARRAY_LENGTH(constraint_row.confkey, 1) = 1
          AND source_column.attname = 'id'
          AND target_column.attname = 'id'
        ORDER BY constraint_row.conname
    LOOP
        IF auth_fk.confdeltype = 'r' THEN
            has_restrict_fk := TRUE;
        ELSE
            EXECUTE pg_catalog.FORMAT(
                'ALTER TABLE public.users DROP CONSTRAINT %I',
                auth_fk.conname
            );
        END IF;
    END LOOP;

    IF NOT has_restrict_fk THEN
        ALTER TABLE public.users
            ADD CONSTRAINT users_id_fkey
            FOREIGN KEY (id)
            REFERENCES auth.users(id)
            ON DELETE RESTRICT
            NOT VALID;
    END IF;

    FOR auth_fk IN
        SELECT constraint_row.conname
        FROM pg_catalog.pg_constraint AS constraint_row
        JOIN pg_catalog.pg_attribute AS source_column
          ON source_column.attrelid = constraint_row.conrelid
         AND source_column.attnum = constraint_row.conkey[1]
        JOIN pg_catalog.pg_attribute AS target_column
          ON target_column.attrelid = constraint_row.confrelid
         AND target_column.attnum = constraint_row.confkey[1]
        WHERE constraint_row.contype = 'f'
          AND constraint_row.conrelid = 'public.users'::REGCLASS
          AND constraint_row.confrelid = 'auth.users'::REGCLASS
          AND constraint_row.confdeltype = 'r'
          AND NOT constraint_row.convalidated
          AND pg_catalog.ARRAY_LENGTH(constraint_row.conkey, 1) = 1
          AND pg_catalog.ARRAY_LENGTH(constraint_row.confkey, 1) = 1
          AND source_column.attname = 'id'
          AND target_column.attname = 'id'
        ORDER BY constraint_row.conname
    LOOP
        EXECUTE pg_catalog.FORMAT(
            'ALTER TABLE public.users VALIDATE CONSTRAINT %I',
            auth_fk.conname
        );
    END LOOP;
END;
$$;

-- The broad public scan policy pre-dated account tombstones. Keep retained
-- ownerless observations available to trusted exports, but never through the
-- anonymous scans table API.
DROP POLICY IF EXISTS "Anyone can read open and live scans"
    ON public.scans;
CREATE POLICY "Anyone can read open and live scans"
ON public.scans
FOR SELECT
USING (
    geoprivacy = 'open'
    AND is_live_capture = TRUE
    AND is_tombstoned = FALSE
);

CREATE OR REPLACE FUNCTION public.apply_user_tombstone(target_user_id UUID)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    PERFORM internal.require_service_role();

    IF target_user_id IS NULL
       OR target_user_id =
            '00000000-0000-0000-0000-000000000000'::UUID THEN
        RAISE EXCEPTION 'A non-zero target user is required.'
            USING ERRCODE = '22023';
    END IF;

    UPDATE public.scans AS scans
    SET user_id = NULL,
        is_tombstoned = TRUE,
        gps_lat_exact = NULL,
        gps_long_exact = NULL,
        gps_elevation = NULL,
        human_intervention_notes = NULL
    WHERE scans.user_id = target_user_id;

    DELETE FROM public.users AS users
    WHERE users.id = target_user_id;
END;
$$;

COMMENT ON FUNCTION public.apply_user_tombstone(UUID) IS
    'Service-only relational anonymization. Retained scans become ownerless tombstones; no synthetic Auth or public user is created.';

REVOKE ALL ON FUNCTION public.apply_user_tombstone(UUID)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.apply_user_tombstone(UUID)
    TO service_role;

-- A production public.users -> auth.users FK is itself an Auth-referencing FK.
-- The catalog-driven Ghost merge must not try to rewrite the source profile's
-- primary key to the already-existing destination profile. All dependent rows
-- are reparented first; the source public profile is then deleted explicitly,
-- and the source Auth identity remains for the durable external cleanup step.
CREATE OR REPLACE FUNCTION internal.reparent_ghost_user_foreign_keys(
    p_ghost_user_id UUID,
    p_target_user_id UUID
)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    foreign_key RECORD;
    has_remaining_rows BOOLEAN;
BEGIN
    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_constraint AS constraint_row
        WHERE constraint_row.contype = 'f'
          AND constraint_row.confrelid IN (
              'public.users'::REGCLASS,
              'auth.users'::REGCLASS
          )
          AND (
              pg_catalog.ARRAY_LENGTH(constraint_row.conkey, 1) <> 1
              OR pg_catalog.ARRAY_LENGTH(constraint_row.confkey, 1) <> 1
          )
          AND constraint_row.conrelid::REGCLASS::TEXT
              NOT LIKE 'auth.%'
    ) THEN
        RAISE EXCEPTION
            'ghost_merge_schema_requires_explicit_composite_fk_support'
            USING ERRCODE = '55000';
    END IF;

    FOR foreign_key IN
        SELECT
            source_namespace.nspname AS schema_name,
            source_table.relname AS table_name,
            source_column.attname AS column_name,
            constraint_row.confrelid
        FROM pg_catalog.pg_constraint AS constraint_row
        JOIN pg_catalog.pg_class AS source_table
          ON source_table.oid = constraint_row.conrelid
        JOIN pg_catalog.pg_namespace AS source_namespace
          ON source_namespace.oid = source_table.relnamespace
        JOIN pg_catalog.pg_attribute AS source_column
          ON source_column.attrelid = constraint_row.conrelid
         AND source_column.attnum = constraint_row.conkey[1]
        JOIN pg_catalog.pg_attribute AS target_column
          ON target_column.attrelid = constraint_row.confrelid
         AND target_column.attnum = constraint_row.confkey[1]
        WHERE constraint_row.contype = 'f'
          AND constraint_row.confrelid IN (
              'public.users'::REGCLASS,
              'auth.users'::REGCLASS
          )
          AND pg_catalog.ARRAY_LENGTH(constraint_row.conkey, 1) = 1
          AND pg_catalog.ARRAY_LENGTH(constraint_row.confkey, 1) = 1
          AND NOT (
              constraint_row.confrelid = 'auth.users'::REGCLASS
              AND source_namespace.nspname = 'auth'
          )
          AND NOT (
              constraint_row.conrelid = 'public.users'::REGCLASS
              AND constraint_row.confrelid = 'auth.users'::REGCLASS
              AND source_column.attname = 'id'
              AND target_column.attname = 'id'
          )
        ORDER BY
            source_namespace.nspname,
            source_table.relname,
            source_column.attname
    LOOP
        EXECUTE pg_catalog.FORMAT(
            'UPDATE %I.%I SET %I = $1 WHERE %I = $2',
            foreign_key.schema_name,
            foreign_key.table_name,
            foreign_key.column_name,
            foreign_key.column_name
        )
        USING p_target_user_id, p_ghost_user_id;
    END LOOP;

    -- Refuse to delete the public profile if a future FK could not be
    -- reparented. The profile's own Auth FK is intentionally ignored because
    -- this routine deletes that child row rather than rewriting its PK.
    FOR foreign_key IN
        SELECT
            source_namespace.nspname AS schema_name,
            source_table.relname AS table_name,
            source_column.attname AS column_name,
            constraint_row.confrelid
        FROM pg_catalog.pg_constraint AS constraint_row
        JOIN pg_catalog.pg_class AS source_table
          ON source_table.oid = constraint_row.conrelid
        JOIN pg_catalog.pg_namespace AS source_namespace
          ON source_namespace.oid = source_table.relnamespace
        JOIN pg_catalog.pg_attribute AS source_column
          ON source_column.attrelid = constraint_row.conrelid
         AND source_column.attnum = constraint_row.conkey[1]
        JOIN pg_catalog.pg_attribute AS target_column
          ON target_column.attrelid = constraint_row.confrelid
         AND target_column.attnum = constraint_row.confkey[1]
        WHERE constraint_row.contype = 'f'
          AND constraint_row.confrelid IN (
              'public.users'::REGCLASS,
              'auth.users'::REGCLASS
          )
          AND pg_catalog.ARRAY_LENGTH(constraint_row.conkey, 1) = 1
          AND pg_catalog.ARRAY_LENGTH(constraint_row.confkey, 1) = 1
          AND NOT (
              constraint_row.confrelid = 'auth.users'::REGCLASS
              AND source_namespace.nspname = 'auth'
          )
          AND NOT (
              constraint_row.conrelid = 'public.users'::REGCLASS
              AND constraint_row.confrelid = 'auth.users'::REGCLASS
              AND source_column.attname = 'id'
              AND target_column.attname = 'id'
          )
    LOOP
        EXECUTE pg_catalog.FORMAT(
            'SELECT EXISTS (SELECT 1 FROM %I.%I WHERE %I = $1)',
            foreign_key.schema_name,
            foreign_key.table_name,
            foreign_key.column_name
        )
        INTO has_remaining_rows
        USING p_ghost_user_id;

        IF has_remaining_rows THEN
            RAISE EXCEPTION
                'ghost_merge_unhandled_reference: %.%.%',
                foreign_key.schema_name,
                foreign_key.table_name,
                foreign_key.column_name
                USING ERRCODE = '55000';
        END IF;
    END LOOP;
END;
$$;

COMMENT ON FUNCTION internal.reparent_ghost_user_foreign_keys(UUID, UUID) IS
    'Catalog-driven Ghost ownership reparenting. The public profile Auth FK is excluded because the source profile is deleted after its dependents move.';

REVOKE ALL ON FUNCTION internal.reparent_ghost_user_foreign_keys(UUID, UUID)
    FROM PUBLIC, anon, authenticated, service_role;

COMMIT;
