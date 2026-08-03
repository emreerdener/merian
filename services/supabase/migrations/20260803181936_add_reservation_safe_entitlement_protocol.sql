SET lock_timeout = '5s';
SET statement_timeout = '30s';

-- Protocol 3 is reservation-safe. Protocol 2 remains a supported presentation
-- only while rollout configuration still requires 2, allowing the schema and
-- Edge Functions to be deployed before the fixed iOS build is required.
ALTER TABLE internal.entitlement_rollout_config
    DROP CONSTRAINT entitlement_rollout_mode_protocol_check;
ALTER TABLE internal.entitlement_rollout_config
    ADD CONSTRAINT entitlement_rollout_mode_protocol_check CHECK (
        (
            entitlement_mode = 'legacy_trial'
            AND required_client_protocol = 0
        )
        OR (
            entitlement_mode = 'complimentary'
            AND required_client_protocol IN (2, 3)
        )
    );

COMMENT ON TABLE internal.entitlement_rollout_config IS
    'Owner-only atomic rollout switch. legacy_trial/protocol 0 supports schema-first deployment; complimentary/protocol 2 accepts supported protocols 2-3 during rollout, and complimentary/protocol 3 requires reservation-safe clients.';

COMMENT ON FUNCTION public.get_entitlement_rollout_service() IS
    'Service-only rollout fence used to require a supported entitlement protocol after complimentary cutover.';

-- Keep the established quota implementation and change only its protocol
-- predicate. Source-drift checks make a future definition change fail the
-- migration rather than silently leave the old exact-match fence in place.
DO $migration$
DECLARE
    function_definition TEXT;
    rewritten_definition TEXT;
    old_fragment CONSTANT TEXT :=
        'AND p_client_protocol IS DISTINCT FROM'
        || pg_catalog.CHR(10)
        || '            rollout.required_client_protocol';
    new_fragment CONSTANT TEXT :=
        'AND ('
        || pg_catalog.CHR(10)
        || '            p_client_protocol IS NULL'
        || pg_catalog.CHR(10)
        || '            OR p_client_protocol < rollout.required_client_protocol'
        || pg_catalog.CHR(10)
        || '            OR p_client_protocol > 3'
        || pg_catalog.CHR(10)
        || '       )';
BEGIN
    SELECT pg_catalog.PG_GET_FUNCTIONDEF(routine.oid)
    INTO STRICT function_definition
    FROM pg_catalog.pg_proc AS routine
    JOIN pg_catalog.pg_namespace AS namespace
      ON namespace.oid = routine.pronamespace
    WHERE namespace.nspname = 'public'
      AND routine.proname = 'reserve_ai_quota'
      AND pg_catalog.PG_GET_FUNCTION_IDENTITY_ARGUMENTS(routine.oid) =
          'p_user_id uuid, p_operation text, p_request_id uuid, p_ip_hash text, p_original_analysis_id uuid, p_flash_fallback_eligible boolean, p_client_protocol integer, p_internal_replay boolean';

    IF pg_catalog.STRPOS(function_definition, old_fragment) = 0 THEN
        RAISE EXCEPTION 'reserve_ai_quota_protocol_source_drift'
            USING ERRCODE = '55000';
    END IF;

    rewritten_definition := pg_catalog.REPLACE(
        function_definition,
        old_fragment,
        new_fragment
    );

    IF rewritten_definition IS NOT DISTINCT FROM function_definition
       OR pg_catalog.STRPOS(rewritten_definition, old_fragment) <> 0 THEN
        RAISE EXCEPTION 'reserve_ai_quota_protocol_rewrite_failed'
            USING ERRCODE = '55000';
    END IF;

    EXECUTE rewritten_definition;
END;
$migration$;

COMMENT ON FUNCTION public.reserve_ai_quota(
    UUID,
    TEXT,
    UUID,
    TEXT,
    UUID,
    BOOLEAN,
    INTEGER,
    BOOLEAN
) IS
    'Service-only AI quota reservation. Public scan calls must present a supported protocol at least as new as rollout configuration and no newer than protocol 3.';

CREATE OR REPLACE FUNCTION public.get_complimentary_scan_states_service(
    p_user_id UUID,
    p_scan_ids UUID[]
)
RETURNS TABLE (
    client_scan_id UUID,
    complimentary_state TEXT
)
LANGUAGE PLPGSQL
STABLE
SECURITY DEFINER
SET search_path = ''
SET statement_timeout = '5s'
AS $$
BEGIN
    PERFORM internal.require_service_role();

    IF p_user_id IS NULL
       OR p_scan_ids IS NULL
       OR pg_catalog.CARDINALITY(p_scan_ids) > 50
       OR pg_catalog.ARRAY_POSITION(p_scan_ids, NULL::UUID) IS NOT NULL THEN
        RAISE EXCEPTION 'complimentary_state_invalid_request'
            USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    SELECT DISTINCT
        requested.client_scan_id,
        usage.state
    FROM pg_catalog.UNNEST(p_scan_ids) AS requested(client_scan_id)
    JOIN internal.complimentary_scan_usage AS usage
      ON usage.user_id = p_user_id
     AND usage.client_scan_id = requested.client_scan_id;
END;
$$;

REVOKE ALL ON FUNCTION public.get_complimentary_scan_states_service(
    UUID,
    UUID[]
) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_complimentary_scan_states_service(
    UUID,
    UUID[]
) TO service_role;

COMMENT ON FUNCTION public.get_complimentary_scan_states_service(
    UUID,
    UUID[]
) IS
    'Service-only owner-scoped bulk funding-state read for authenticated check-scan-status recovery.';

INSERT INTO internal.privileged_routine_grants (
    role_name,
    routine_signature,
    purpose
)
VALUES (
    'service_role',
    'public.get_complimentary_scan_states_service(uuid,uuid[])',
    'Edge-only owner-scoped bulk read of complimentary hold settlement state for deferred-scan scheduling.'
)
ON CONFLICT (role_name, routine_signature) DO UPDATE
SET purpose = EXCLUDED.purpose;

UPDATE internal.privileged_routine_grants
SET purpose =
    'Edge-only protocol-2-to-3 quota reservation with original analysis and complimentary usage linkage.'
WHERE role_name = 'service_role'
  AND routine_signature =
      'public.reserve_ai_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean)';

NOTIFY pgrst, 'reload schema';

RESET statement_timeout;
RESET lock_timeout;
