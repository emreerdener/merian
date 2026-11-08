-- Shared selectors only: keep all callers at their existing lock and error
-- positions. Full initial assignment freezing and pre-funding assertion are
-- separate dependencies; these helpers do not authorize either.
SET lock_timeout = '5s';
SET statement_timeout = '2min';

CREATE FUNCTION internal.resolve_quota_policy(p_operation TEXT,p_effective_plan TEXT)
RETURNS internal.ai_quota_policies LANGUAGE PLPGSQL SECURITY INVOKER SET search_path = '' AS $function$
DECLARE policy_row internal.ai_quota_policies;
BEGIN
    SELECT policies.*
    INTO policy_row
    FROM internal.ai_quota_policies AS policies
    WHERE policies.operation = p_operation
      AND policies.effective_plan = p_effective_plan
    FOR SHARE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ai_quota_policy_missing'
            USING ERRCODE = 'P0001';
    END IF;
    IF NOT policy_row.enabled THEN
        RAISE EXCEPTION 'ai_quota_policy_disabled'
            USING ERRCODE = 'P0001';
    END IF;
    IF NOT policy_row.allowed THEN
        RAISE EXCEPTION 'ai_entitlement_required'
            USING ERRCODE = 'P0001';
    END IF;

    RETURN policy_row;
END;
$function$;

CREATE FUNCTION internal.resolve_identification_provider_binding(
    p_operation TEXT,p_effective_plan TEXT,p_model TEXT,p_policy_version BIGINT,p_input_profile TEXT
) RETURNS internal.identification_provider_bindings LANGUAGE PLPGSQL SECURITY INVOKER SET search_path = '' AS $function$
DECLARE assignment internal.identification_provider_bindings;
BEGIN
        SELECT bindings.* INTO assignment
        FROM internal.identification_provider_bindings AS bindings
        WHERE bindings.operation = p_operation
          AND bindings.effective_plan = p_effective_plan
          AND bindings.model = p_model
          AND bindings.policy_version = p_policy_version
          AND bindings.input_profile = p_input_profile
        FOR SHARE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'ai_provider_assignment_unavailable' USING ERRCODE = 'P0001';
        END IF;
    RETURN assignment;
END;
$function$;

REVOKE ALL ON FUNCTION internal.resolve_quota_policy(TEXT,TEXT),
    internal.resolve_identification_provider_binding(TEXT,TEXT,TEXT,BIGINT,TEXT)
    FROM PUBLIC,anon,authenticated,service_role;

DO $migration$
DECLARE definition TEXT; old_fragment TEXT; new_fragment TEXT;
BEGIN
    SELECT pg_catalog.pg_get_functiondef('internal.reserve_ai_quota_core(uuid,text,uuid,text)'::REGPROCEDURE)
    INTO STRICT definition;
    old_fragment := $policy$    SELECT policies.*
    INTO policy_row
    FROM internal.ai_quota_policies AS policies
    WHERE policies.operation = p_operation
      AND policies.effective_plan = resolved_plan
    FOR SHARE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'ai_quota_policy_missing'
            USING ERRCODE = 'P0001';
    END IF;
    IF NOT policy_row.enabled THEN
        RAISE EXCEPTION 'ai_quota_policy_disabled'
            USING ERRCODE = 'P0001';
    END IF;
    IF NOT policy_row.allowed THEN
        RAISE EXCEPTION 'ai_entitlement_required'
            USING ERRCODE = 'P0001';
    END IF;
$policy$;
    new_fragment := $policy$    SELECT selected.* INTO policy_row
    FROM internal.resolve_quota_policy(p_operation,resolved_plan) AS selected;
$policy$;
    IF (pg_catalog.length(definition)-pg_catalog.length(pg_catalog.replace(definition,old_fragment,'')))
        / pg_catalog.length(old_fragment) <> 1 THEN
        RAISE EXCEPTION 'initial assignment policy source drift';
    END IF;
    EXECUTE pg_catalog.replace(definition,old_fragment,new_fragment);

    SELECT pg_catalog.pg_get_functiondef('public.reserve_identification_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean,text,text,integer)'::REGPROCEDURE)
    INTO STRICT definition;
    old_fragment := $binding$        SELECT bindings.* INTO assignment
        FROM internal.identification_provider_bindings AS bindings
        WHERE bindings.operation = p_operation
          AND bindings.effective_plan = admitted.effective_plan
          AND bindings.model = admitted.model
          AND bindings.policy_version = admitted.policy_version
          AND bindings.input_profile = p_input_profile
        FOR SHARE;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'ai_provider_assignment_unavailable' USING ERRCODE = 'P0001';
        END IF;
$binding$;
    new_fragment := $binding$        SELECT selected.* INTO assignment
        FROM internal.resolve_identification_provider_binding(
            p_operation,admitted.effective_plan,admitted.model,admitted.policy_version,p_input_profile
        ) AS selected;
$binding$;
    IF (pg_catalog.length(definition)-pg_catalog.length(pg_catalog.replace(definition,old_fragment,'')))
        / pg_catalog.length(old_fragment) <> 1 THEN
        RAISE EXCEPTION 'initial assignment binding source drift';
    END IF;
    EXECUTE pg_catalog.replace(definition,old_fragment,new_fragment);
END;
$migration$;

RESET statement_timeout;
RESET lock_timeout;
