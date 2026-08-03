SET lock_timeout = '5s';
SET statement_timeout = '30s';

-- Existing rows can predate scan-owner validation.  Keep only memberships whose
-- two parents have the same owner before enforcing the invariant for new rows.
DELETE FROM public.collection_scans AS membership
USING public.collections AS collection,
      public.scans AS scan
WHERE collection.id = membership.collection_id
  AND scan.id = membership.scan_id
  AND collection.user_id IS DISTINCT FROM scan.user_id;

-- A service-key request bypasses RLS.  Remove its table-wide UPDATE capability
-- so neither PostgREST nor future Edge code can reparent a collection directly.
-- The ghost-account merge remains able to reparent through its reviewed
-- SECURITY DEFINER implementation.
REVOKE UPDATE ON TABLE public.collections FROM service_role;
REVOKE UPDATE (id, user_id, name, created_at)
    ON TABLE public.collections FROM service_role;
GRANT UPDATE (name, created_at) ON TABLE public.collections TO service_role;

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
            parsed.ordinality
        FROM pg_catalog.JSONB_TO_RECORDSET(p_collections)
            WITH ORDINALITY AS parsed(
                id UUID,
                name TEXT,
                created_at TIMESTAMPTZ,
                ordinality BIGINT
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

COMMENT ON FUNCTION public.upsert_owned_collections(UUID, JSONB) IS
    'Service-only atomic collection upsert. Existing foreign IDs are returned as rejected and are never reparented.';

REVOKE ALL ON FUNCTION public.upsert_owned_collections(UUID, JSONB)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.upsert_owned_collections(UUID, JSONB)
    TO service_role;

CREATE OR REPLACE FUNCTION public.enforce_collection_scan_owner_match()
RETURNS TRIGGER
LANGUAGE PLPGSQL
VOLATILE
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
    collection_owner UUID;
    scan_owner UUID;
BEGIN
    SELECT collection.user_id
    INTO collection_owner
    FROM public.collections AS collection
    WHERE collection.id = NEW.collection_id;

    SELECT scan.user_id
    INTO scan_owner
    FROM public.scans AS scan
    WHERE scan.id = NEW.scan_id;

    IF collection_owner IS NULL
       OR scan_owner IS NULL
       OR collection_owner IS DISTINCT FROM scan_owner THEN
        RAISE EXCEPTION
            'collection and scan owners must match'
            USING ERRCODE = '23514';
    END IF;

    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_collection_scan_owner_match() IS
    'Invoker trigger enforcing that every collection membership joins records owned by the same account.';

REVOKE ALL ON FUNCTION public.enforce_collection_scan_owner_match()
    FROM PUBLIC, anon, authenticated, service_role;

DROP TRIGGER IF EXISTS enforce_collection_scan_owner_match
    ON public.collection_scans;
CREATE TRIGGER enforce_collection_scan_owner_match
BEFORE INSERT OR UPDATE OF collection_id, scan_id
ON public.collection_scans
FOR EACH ROW
EXECUTE FUNCTION public.enforce_collection_scan_owner_match();

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
    ON CONFLICT (collection_id, scan_id) DO NOTHING
    RETURNING membership.collection_id, membership.scan_id;
END;
$$;

COMMENT ON FUNCTION public.insert_owned_collection_scans(UUID, JSONB) IS
    'Service-only membership insert that admits rows only when both parent records belong to the requested owner.';

REVOKE ALL ON FUNCTION public.insert_owned_collection_scans(UUID, JSONB)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.insert_owned_collection_scans(UUID, JSONB)
    TO service_role;

-- Replace the old collection-only FOR ALL policy.  Inserts now require both
-- parents to belong to the caller; updates are intentionally unsupported.
DROP POLICY IF EXISTS "Users can fully manage their own collection scans"
    ON public.collection_scans;

CREATE POLICY "Users can read their own collection scans"
ON public.collection_scans
FOR SELECT
TO authenticated
USING (
    EXISTS (
        SELECT 1
        FROM public.collections AS collection
        WHERE collection.id = collection_id
          AND collection.user_id = (SELECT auth.uid())
    )
);

CREATE POLICY "Users can delete their own collection scans"
ON public.collection_scans
FOR DELETE
TO authenticated
USING (
    EXISTS (
        SELECT 1
        FROM public.collections AS collection
        WHERE collection.id = collection_id
          AND collection.user_id = (SELECT auth.uid())
    )
);

CREATE POLICY "Users can add scans to their own collections"
ON public.collection_scans
FOR INSERT
TO authenticated
WITH CHECK (
    EXISTS (
        SELECT 1
        FROM public.collections AS collection
        WHERE collection.id = collection_id
          AND collection.user_id = (SELECT auth.uid())
    )
    AND EXISTS (
        SELECT 1
        FROM public.scans AS scan
        WHERE scan.id = scan_id
          AND scan.user_id = (SELECT auth.uid())
    )
);

NOTIFY pgrst, 'reload schema';

RESET statement_timeout;
RESET lock_timeout;
