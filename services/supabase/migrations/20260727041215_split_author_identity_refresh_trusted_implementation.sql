-- The service-role RPC and two trusted database workflows need the same
-- identity-refresh implementation. Keep the externally executable function
-- guarded, while trusted trigger/merge code calls an unexposed helper whose
-- EXECUTE privilege is denied to every API role.
BEGIN;

CREATE OR REPLACE FUNCTION internal.refresh_public_author_identity(
    target_user_id UUID
)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    auth_meta JSONB;
    existing_name TEXT;
    existing_source TEXT;
    existing_username TEXT;
    existing_custom_avatar_url TEXT;
    resolved_name TEXT;
    resolved_source TEXT;
    resolved_avatar_url TEXT;
BEGIN
    SELECT
        user_row.public_author_name,
        user_row.public_identity_source,
        user_row.public_username,
        user_row.custom_avatar_url
    INTO
        existing_name,
        existing_source,
        existing_username,
        existing_custom_avatar_url
    FROM public.users AS user_row
    WHERE user_row.id = target_user_id;

    IF NOT FOUND THEN
        RETURN;
    END IF;

    auth_meta := COALESCE(
        public.public_author_metadata_for_auth_user(target_user_id),
        '{}'::JSONB
    );
    resolved_avatar_url := public.resolve_public_avatar_url(
        existing_custom_avatar_url,
        auth_meta
    );

    IF existing_source = 'display_name'
       AND existing_name IS NOT NULL
       AND BTRIM(existing_name) <> '' THEN
        UPDATE public.users AS user_row
        SET public_avatar_url = resolved_avatar_url
        WHERE user_row.id = target_user_id
          AND user_row.public_avatar_url IS DISTINCT FROM resolved_avatar_url;
        RETURN;
    END IF;

    SELECT identity.author_name, identity.identity_source
    INTO resolved_name, resolved_source
    FROM public.derive_public_author_identity(
        auth_meta,
        target_user_id
    ) AS identity;

    IF resolved_source = 'alias' THEN
        resolved_name := COALESCE(
            NULLIF(BTRIM(existing_username), ''),
            public.build_default_public_username(target_user_id)
        );
    END IF;

    UPDATE public.users AS user_row
    SET public_author_name = resolved_name,
        public_identity_source = resolved_source,
        public_avatar_url = resolved_avatar_url
    WHERE user_row.id = target_user_id
      AND (
          user_row.public_author_name IS DISTINCT FROM resolved_name
          OR user_row.public_identity_source IS DISTINCT FROM resolved_source
          OR user_row.public_avatar_url IS DISTINCT FROM resolved_avatar_url
      );
END;
$$;

REVOKE ALL ON FUNCTION internal.refresh_public_author_identity(UUID)
    FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.refresh_public_author_identity(
    target_user_id UUID
)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    PERFORM internal.require_service_role();
    PERFORM internal.refresh_public_author_identity(target_user_id);
END;
$$;

REVOKE ALL ON FUNCTION public.refresh_public_author_identity(UUID)
    FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.refresh_public_author_identity(UUID)
    TO service_role;

-- Preserve the large, already-reviewed merge and Auth-trigger implementations
-- while changing only their trusted refresh dependency.
DO $migration$
DECLARE
    routine_row RECORD;
    function_definition TEXT;
    rewritten_definition TEXT;
BEGIN
    FOR routine_row IN
        SELECT *
        FROM (
            VALUES
                (
                    'internal.perform_ghost_profile_merge(uuid,uuid)',
                    'PERFORM public.refresh_public_author_identity(p_target_user_id);',
                    'PERFORM internal.refresh_public_author_identity(p_target_user_id);'
                ),
                (
                    'public.handle_auth_user_updated()',
                    'PERFORM public.refresh_public_author_identity(NEW.id);',
                    'PERFORM internal.refresh_public_author_identity(NEW.id);'
                )
        ) AS dependency(
            routine_signature,
            guarded_call,
            trusted_call
        )
    LOOP
        SELECT pg_catalog.PG_GET_FUNCTIONDEF(routine_oid)
        INTO STRICT function_definition
        FROM (
            SELECT pg_catalog.TO_REGPROCEDURE(
                routine_row.routine_signature
            ) AS routine_oid
        ) AS resolved
        WHERE routine_oid IS NOT NULL;

        rewritten_definition := pg_catalog.REPLACE(
            function_definition,
            routine_row.guarded_call,
            routine_row.trusted_call
        );

        IF rewritten_definition IS NOT DISTINCT FROM function_definition THEN
            RAISE EXCEPTION
                'Could not rewire trusted identity refresh in %',
                routine_row.routine_signature;
        END IF;

        EXECUTE rewritten_definition;
    END LOOP;
END;
$migration$;

COMMIT;
