SET lock_timeout = '5s';
SET statement_timeout = '30s';

-- PostgreSQL does not allow a column-definition list directly beside WITH
-- ORDINALITY.  Preserve the API's last-occurrence-wins semantics by deriving
-- ordinality from the JSON array first, then expanding each JSON object.
CREATE OR REPLACE FUNCTION public.upsert_owned_collections(
    p_user_id UUID,
    p_collections JSONB
)
RETURNS TABLE (
    collection_id UUID,
    accepted BOOLEAN
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

    IF p_collections IS NULL
       OR pg_catalog.JSONB_TYPEOF(p_collections) <> 'array' THEN
        RAISE EXCEPTION 'p_collections must be a JSON array'
            USING ERRCODE = '22023';
    END IF;

    IF pg_catalog.JSONB_ARRAY_LENGTH(p_collections) > 200 THEN
        RAISE EXCEPTION 'p_collections exceeds the 200-row limit'
            USING ERRCODE = '22023';
    END IF;

    RETURN QUERY
    WITH input_rows AS MATERIALIZED (
        SELECT
            parsed.id,
            parsed.name,
            parsed.created_at,
            source.ordinality
        FROM pg_catalog.JSONB_ARRAY_ELEMENTS(p_collections)
            WITH ORDINALITY AS source(value, ordinality)
        CROSS JOIN LATERAL pg_catalog.JSONB_TO_RECORD(source.value) AS parsed(
            id UUID,
            name TEXT,
            created_at TIMESTAMPTZ
        )
    ),
    deduplicated AS MATERIALIZED (
        SELECT DISTINCT ON (input_rows.id)
            input_rows.id,
            input_rows.name,
            input_rows.created_at,
            input_rows.ordinality
        FROM input_rows
        ORDER BY input_rows.id, input_rows.ordinality DESC
    ),
    written AS (
        INSERT INTO public.collections AS existing (
            id,
            user_id,
            name,
            created_at
        )
        SELECT
            deduplicated.id,
            p_user_id,
            deduplicated.name,
            deduplicated.created_at
        FROM deduplicated
        ORDER BY deduplicated.id
        ON CONFLICT (id) DO UPDATE
        SET name = EXCLUDED.name,
            created_at = EXCLUDED.created_at
        WHERE existing.user_id = EXCLUDED.user_id
        RETURNING existing.id
    )
    SELECT
        deduplicated.id,
        written.id IS NOT NULL
    FROM deduplicated
    LEFT JOIN written ON written.id = deduplicated.id
    ORDER BY deduplicated.ordinality;
END;
$$;

RESET statement_timeout;
RESET lock_timeout;
