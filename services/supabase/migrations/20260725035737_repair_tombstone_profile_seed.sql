-- The tombstone owner was previously created lazily by
-- public.apply_user_tombstone with only the columns that existed in the initial
-- schema. Later NOT NULL public identity columns made every first deletion on a
-- fresh database fail before anonymization. Seed the infrastructure row once,
-- with the complete current identity contract, and keep routine execution free
-- from schema-coupled profile creation.
WITH tombstone_identity AS (
    SELECT public.build_unique_public_username(
        'deleted_account',
        '00000000-0000-0000-0000-000000000000'::UUID
    ) AS public_username
)
INSERT INTO public.users AS tombstone_user (
    id,
    public_username,
    public_author_name,
    public_identity_source
)
SELECT
    '00000000-0000-0000-0000-000000000000'::UUID,
    tombstone_identity.public_username,
    tombstone_identity.public_username,
    'alias'
FROM tombstone_identity
ON CONFLICT (id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.apply_user_tombstone(target_user_id UUID)
RETURNS VOID
LANGUAGE PLPGSQL
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    tombstone_user_id CONSTANT UUID :=
        '00000000-0000-0000-0000-000000000000'::UUID;
BEGIN
    PERFORM internal.require_service_role();

    IF target_user_id IS NULL
       OR target_user_id = tombstone_user_id THEN
        RAISE EXCEPTION 'A non-tombstone target user is required.'
            USING ERRCODE = '22023';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.users AS tombstone_user
        WHERE tombstone_user.id = tombstone_user_id
    ) THEN
        RAISE EXCEPTION 'account_deletion_tombstone_missing'
            USING ERRCODE = '55000';
    END IF;

    UPDATE public.scans
    SET user_id = tombstone_user_id,
        is_tombstoned = TRUE
    WHERE user_id = target_user_id;

    DELETE FROM public.users
    WHERE id = target_user_id;
END;
$$;

COMMENT ON FUNCTION public.apply_user_tombstone(UUID) IS
    'Service-only relational anonymization. The migration-seeded tombstone owner must exist before scans move and the target profile is deleted.';

REVOKE ALL ON FUNCTION public.apply_user_tombstone(UUID)
    FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.apply_user_tombstone(UUID)
    TO service_role;
