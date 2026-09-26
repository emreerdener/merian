-- Identification reports the permission missing for its app-assigned recipient.
-- Legacy Gemini callers and the consent ledger keep their existing contracts.
CREATE OR REPLACE FUNCTION internal.require_identification_processor_consent(
    p_user_id UUID,
    p_processor_permission TEXT
)
RETURNS VOID
LANGUAGE PLPGSQL
STABLE
SECURITY INVOKER
SET search_path = ''
AS $function$
BEGIN
    IF p_user_id IS NULL OR p_processor_permission IS NULL
       OR p_processor_permission NOT IN ('google_gemini', 'openai') THEN
        RAISE EXCEPTION 'ai_provider_assignment_unavailable' USING ERRCODE = 'P0001';
    END IF;
    BEGIN
        PERFORM internal.require_current_ai_consent(p_user_id, p_processor_permission);
    EXCEPTION WHEN SQLSTATE 'P0001' THEN
        IF SQLERRM = 'ai_consent_required' AND p_processor_permission = 'openai' THEN
            RAISE EXCEPTION 'ai_openai_consent_required' USING ERRCODE = 'P0001';
        END IF;
        RAISE;
    END;
END;
$function$;
REVOKE ALL ON FUNCTION internal.require_identification_processor_consent(UUID, TEXT)
    FROM PUBLIC, anon, authenticated, service_role;
COMMENT ON FUNCTION internal.require_identification_processor_consent(UUID, TEXT) IS
    'Closed recipient-specific identification denial; validates but never selects a provider or grants processing permission.';

-- Patch only the two recipient checks in each reviewed RPC overload. Keep
-- entitlement, quota, replay, legacy Gemini, grants and search paths intact.
DO $patch$
DECLARE
    signature TEXT;
    definition TEXT;
    fragment TEXT;
BEGIN
    FOREACH signature IN ARRAY ARRAY[
        'public.reserve_identification_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean)',
        'public.reserve_identification_quota(uuid,text,uuid,text,uuid,boolean,integer,boolean,text)'
    ] LOOP
        definition := pg_catalog.PG_GET_FUNCTIONDEF(pg_catalog.TO_REGPROCEDURE(signature));
        FOREACH fragment IN ARRAY ARRAY[
            'PERFORM internal.require_current_ai_consent(p_user_id, assignment.processor_permission);',
            'PERFORM internal.require_current_ai_consent(p_user_id, attempt.processor_permission);'
        ] LOOP
            IF definition IS NULL OR
                (pg_catalog.LENGTH(definition) - pg_catalog.LENGTH(pg_catalog.REPLACE(definition, fragment, '')))
                    / pg_catalog.LENGTH(fragment) <> 1 THEN
                RAISE EXCEPTION 'identification recipient check drift: %', signature;
            END IF;
            definition := pg_catalog.REPLACE(definition, fragment,
                pg_catalog.REPLACE(fragment, 'require_current_ai_consent', 'require_identification_processor_consent'));
        END LOOP;
        EXECUTE definition;
    END LOOP;
END;
$patch$;
