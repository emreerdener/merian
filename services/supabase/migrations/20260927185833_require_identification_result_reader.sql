-- A submitting device's capability does not protect another, older reader of
-- the same account. Reject a query that reaches an otherwise-visible V2 row;
-- never filter that observation, strip provenance, or invent Gemini settings.
SET lock_timeout = '5s';
SET statement_timeout = '5min';

CREATE FUNCTION internal.require_identification_result_reader(p_provenance JSONB)
RETURNS BOOLEAN
LANGUAGE plpgsql
VOLATILE
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    headers_text TEXT;
    headers JSONB;
BEGIN
    IF p_provenance IS NULL OR p_provenance -> 'version' = '1'::JSONB THEN
        RETURN TRUE;
    END IF;

    -- PostgREST normalizes header names. A capability claim never supplies
    -- identity or changes row visibility. Malformed/missing claims fail closed.
    headers_text := pg_catalog.CURRENT_SETTING('request.headers', TRUE);
    IF p_provenance -> 'version' = '2'::JSONB
       AND pg_catalog.OCTET_LENGTH(headers_text) <= 32768 THEN
        BEGIN
            headers := NULLIF(headers_text, '')::JSONB;
        EXCEPTION WHEN invalid_text_representation THEN
            headers := NULL;
        END;
        IF pg_catalog.JSONB_TYPEOF(headers) = 'object'
           AND headers -> 'x-merian-identification-protocol' = '"4"'::JSONB THEN
            RETURN TRUE;
        END IF;
    END IF;

    RAISE SQLSTATE 'PT426' USING
        MESSAGE = 'client_update_required',
        HINT = 'Update Naturebook to read this identification.';
END;
$$;

REVOKE ALL ON FUNCTION internal.require_identification_result_reader(JSONB)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION internal.require_identification_result_reader(JSONB)
    TO anon, authenticated;

-- A third permissive read policy could bypass the compatibility check. Refuse
-- an unexpected catalog instead of silently installing a partial boundary.
DO $migration$
BEGIN
    IF (SELECT pg_catalog.COUNT(*) FROM pg_catalog.pg_policy
        WHERE polrelid = 'public.scans'::REGCLASS AND polcmd IN ('r', '*')) <> 2 THEN
        RAISE EXCEPTION 'unexpected_scan_reader_policies';
    END IF;
END;
$migration$;

ALTER POLICY "Users can fully read their own private scans" ON public.scans
USING (
    CASE WHEN (SELECT auth.uid()) = user_id THEN
        internal.require_identification_result_reader(identification_provenance)
    ELSE FALSE END
);

ALTER POLICY "Anyone can read open and live scans" ON public.scans
USING (
    CASE WHEN geoprivacy = 'open' AND is_live_capture = TRUE AND is_tombstoned = FALSE THEN
        internal.require_identification_result_reader(identification_provenance)
    ELSE FALSE END
);

COMMENT ON FUNCTION internal.require_identification_result_reader(JSONB) IS
    'Read compatibility only, after the existing RLS visibility predicate: legacy/V1 unchanged; V2 requires identification protocol 4 or fails the entire query with PT426. Does not authorize a provider or grant access to another owner. Service-owned projections retain their existing role and grants.';

RESET lock_timeout;
RESET statement_timeout;
