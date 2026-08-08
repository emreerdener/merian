-- `get_field_trip_capture_context(uuid)` intentionally remains SECURITY
-- INVOKER. The complimentary-entitlement cutover rewired its Pro predicate to
-- this private helper, so the service-role caller needs execute privilege on
-- that one transitive dependency. Keep direct client roles denied.
DO $migration$
DECLARE
    capture_context_oid OID := pg_catalog.TO_REGPROCEDURE(
        'public.get_field_trip_capture_context(uuid)'
    );
    entitlement_helper_oid OID := pg_catalog.TO_REGPROCEDURE(
        'internal.user_has_effective_pro(uuid)'
    );
    capture_context_definition TEXT;
BEGIN
    IF capture_context_oid IS NULL OR entitlement_helper_oid IS NULL THEN
        RAISE EXCEPTION 'field_trip_capture_entitlement_dependency_missing'
            USING ERRCODE = '55000';
    END IF;

    SELECT pg_catalog.PG_GET_FUNCTIONDEF(capture_context_oid)
    INTO STRICT capture_context_definition;

    IF (
        SELECT routine.prosecdef
        FROM pg_catalog.pg_proc AS routine
        WHERE routine.oid = capture_context_oid
    ) OR NOT (
        SELECT routine.prosecdef
        FROM pg_catalog.pg_proc AS routine
        WHERE routine.oid = entitlement_helper_oid
    ) OR pg_catalog.STRPOS(
        capture_context_definition,
        'internal.user_has_effective_pro('
    ) = 0 THEN
        RAISE EXCEPTION 'field_trip_capture_entitlement_dependency_drift'
            USING ERRCODE = '55000';
    END IF;

    IF pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'anon',
        entitlement_helper_oid,
        'EXECUTE'
    ) OR pg_catalog.HAS_FUNCTION_PRIVILEGE(
        'authenticated',
        entitlement_helper_oid,
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION 'field_trip_capture_entitlement_helper_acl_unsafe'
            USING ERRCODE = '55000';
    END IF;
END;
$migration$;

REVOKE ALL ON FUNCTION internal.user_has_effective_pro(UUID)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION internal.user_has_effective_pro(UUID)
    TO service_role;

COMMENT ON FUNCTION internal.user_has_effective_pro(UUID) IS
    'Private functional-Pro predicate. service_role execute is limited to SECURITY INVOKER server projections such as Field trip capture context; direct client roles remain denied.';
