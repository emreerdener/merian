-- Supabase now requires public-schema Data API privileges to be declared
-- explicitly. Reconstruct the exact scan-table ACL instead of depending on
-- project-era automatic grants: clients may read only rows admitted by RLS,
-- authenticated rolling clients retain five bounded metadata writes, and
-- service-owned Edge ingestion retains canonical CRUD access.

SET lock_timeout = '5s';
SET statement_timeout = '5min';

REVOKE ALL PRIVILEGES
    ON TABLE public.scans
    FROM PUBLIC, anon, authenticated, service_role;

-- Table-level REVOKE does not remove historical column-level grants. Clear
-- every column-granular privilege before installing the reviewed allowlist.
DO $migration$
DECLARE
    scan_column_list TEXT;
    column_privilege TEXT;
BEGIN
    SELECT pg_catalog.STRING_AGG(
        pg_catalog.FORMAT('%I', attributes.attname),
        ', '
        ORDER BY attributes.attnum
    )
    INTO scan_column_list
    FROM pg_catalog.pg_attribute AS attributes
    WHERE attributes.attrelid = 'public.scans'::REGCLASS
      AND attributes.attnum > 0
      AND NOT attributes.attisdropped;

    IF scan_column_list IS NULL THEN
        RAISE EXCEPTION 'public.scans has no grantable columns';
    END IF;

    FOREACH column_privilege IN ARRAY ARRAY[
        'SELECT',
        'INSERT',
        'UPDATE',
        'REFERENCES'
    ]::TEXT[]
    LOOP
        EXECUTE pg_catalog.FORMAT(
            'REVOKE %s (%s) ON TABLE public.scans '
            || 'FROM PUBLIC, anon, authenticated, service_role',
            column_privilege,
            scan_column_list
        );
    END LOOP;
END;
$migration$;

GRANT SELECT
    ON TABLE public.scans
    TO anon, authenticated, service_role;

GRANT UPDATE (
    custom_tags,
    user_identification_override,
    user_confirmed_identification,
    confirmed_species_id,
    user_review_state
) ON TABLE public.scans TO authenticated;

GRANT INSERT, UPDATE, DELETE
    ON TABLE public.scans
    TO service_role;

RESET lock_timeout;
RESET statement_timeout;
