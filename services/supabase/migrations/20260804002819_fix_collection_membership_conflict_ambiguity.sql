SET lock_timeout = '5s';
SET statement_timeout = '30s';

-- The output column names of a RETURNS TABLE function are PL/pgSQL variables.
-- Use the named primary-key constraint instead of an unqualified column list
-- so the guarded insert remains executable under PostgreSQL's ambiguity rules.
CREATE OR REPLACE FUNCTION public.insert_owned_collection_scans(
    p_user_id UUID,
    p_rows JSONB
)
RETURNS TABLE (
    collection_id UUID,
    scan_id UUID
)
LANGUAGE PLPGSQL
VOLATILE
SECURITY INVOKER
SET search_path = ''
AS $$
BEGIN
    IF p_user_id IS NULL THEN
        RAISE EXCEPTION 'p_user_id is required'
            USING ERRCODE = '22023';
    END IF;

    IF p_rows IS NULL OR pg_catalog.JSONB_TYPEOF(p_rows) <> 'array' THEN
        RAISE EXCEPTION 'p_rows must be a JSON array'
            USING ERRCODE = '22023';
    END IF;

    IF pg_catalog.JSONB_ARRAY_LENGTH(p_rows) > 1000 THEN
        RAISE EXCEPTION 'p_rows exceeds the 1000-row limit'
            USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    WITH requested AS MATERIALIZED (
        SELECT DISTINCT
            parsed.collection_id,
            parsed.scan_id
        FROM pg_catalog.JSONB_TO_RECORDSET(p_rows) AS parsed(
            collection_id UUID,
            scan_id UUID
        )
    ),
    admitted AS MATERIALIZED (
        SELECT
            requested.collection_id,
            requested.scan_id
        FROM requested
        JOIN public.collections AS collection
          ON collection.id = requested.collection_id
         AND collection.user_id = p_user_id
        JOIN public.scans AS scan
          ON scan.id = requested.scan_id
         AND scan.user_id = p_user_id
        ORDER BY requested.collection_id, requested.scan_id
    )
    INSERT INTO public.collection_scans AS membership (
        collection_id,
        scan_id
    )
    SELECT admitted.collection_id, admitted.scan_id
    FROM admitted
    ON CONFLICT ON CONSTRAINT collection_scans_pkey DO NOTHING
    RETURNING membership.collection_id, membership.scan_id;
END;
$$;

RESET statement_timeout;
RESET lock_timeout;
