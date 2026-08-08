-- `get_field_trip_capture_context(uuid)` is deliberately SECURITY INVOKER.
-- The earlier entitlement repair restored the private helper EXECUTE edge, but
-- the hardened public-schema defaults also require an explicit read allowlist
-- for every relation used by the projection. Keep the caller service-only and
-- preserve the projection's invoker security mode.

SET lock_timeout = '10s';
SET statement_timeout = '2min';

DO $migration$
DECLARE
    capture_context_oid OID := pg_catalog.TO_REGPROCEDURE(
        'public.get_field_trip_capture_context(uuid)'
    );
    capture_context_definition TEXT;
    expected_relation TEXT;
BEGIN
    IF capture_context_oid IS NULL THEN
        RAISE EXCEPTION 'field_trip_capture_context_source_function_missing'
            USING ERRCODE = '55000';
    END IF;

    SELECT pg_catalog.PG_GET_FUNCTIONDEF(capture_context_oid)
    INTO STRICT capture_context_definition;

    IF (
        SELECT routine.prosecdef
        FROM pg_catalog.pg_proc AS routine
        WHERE routine.oid = capture_context_oid
    ) OR pg_catalog.STRPOS(
        capture_context_definition,
        'internal.user_has_effective_pro('
    ) = 0 THEN
        RAISE EXCEPTION 'field_trip_capture_context_source_shape_drift'
            USING ERRCODE = '55000';
    END IF;

    FOREACH expected_relation IN ARRAY ARRAY[
        'public.users',
        'public.user_field_trips',
        'public.field_trip_templates',
        'public.field_trip_levels',
        'public.user_field_trip_item_completions',
        'public.field_trip_checklist_items'
    ]
    LOOP
        IF pg_catalog.STRPOS(
            capture_context_definition,
            expected_relation
        ) = 0 THEN
            RAISE EXCEPTION
                'field_trip_capture_context_source_relation_drift: %',
                expected_relation
                USING ERRCODE = '55000';
        END IF;
    END LOOP;

    IF pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        capture_context_oid,
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        capture_context_oid,
        'EXECUTE'
    ) OR NOT pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'service_role',
        capture_context_oid,
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'field_trip_capture_context_source_acl_unsafe'
            USING ERRCODE = '55000';
    END IF;
END;
$migration$;

GRANT SELECT ON TABLE
    public.users,
    public.user_field_trips,
    public.field_trip_templates,
    public.field_trip_levels,
    public.user_field_trip_item_completions,
    public.field_trip_checklist_items
TO service_role;

COMMENT ON FUNCTION public.get_field_trip_capture_context(UUID) IS
    'Private service-role SECURITY INVOKER capture context. Its exact source relations grant SELECT only to the server caller; the payload omits scan evidence, media, location, and notes.';

RESET statement_timeout;
RESET lock_timeout;
