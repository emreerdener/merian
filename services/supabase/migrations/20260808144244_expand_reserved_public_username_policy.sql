SET lock_timeout = '10s';
SET statement_timeout = '5min';

CREATE OR REPLACE FUNCTION public.is_reserved_public_username(candidate_username TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
    canonical_username TEXT := pg_catalog.LOWER(
        pg_catalog.BTRIM(COALESCE(candidate_username, ''))
    );
    reserved_exact CONSTANT TEXT[] := ARRAY[
        'null',
        'undefined'
    ];
    reserved_brands CONSTANT TEXT[] := ARRAY[
        'explore',
        'merian',
        'naturebook',
        'naturebookearth'
    ];
    reserved_roles CONSTANT TEXT[] := ARRAY[
        'abuse',
        'account',
        'accounts',
        'admin',
        'administrator',
        'api',
        'auth',
        'billing',
        'bot',
        'contact',
        'customer_service',
        'customer_support',
        'developer',
        'developers',
        'help',
        'legal',
        'moderation',
        'moderator',
        'notifications',
        'official',
        'press',
        'privacy',
        'root',
        'safety',
        'security',
        'staff',
        'status',
        'support',
        'system',
        'team',
        'trust',
        'verified',
        'verify'
    ];
    reserved_brand TEXT;
    reserved_role TEXT;
BEGIN
    IF canonical_username = ANY (reserved_exact)
        OR canonical_username = ANY (reserved_brands)
        OR canonical_username = ANY (reserved_roles)
    THEN
        RETURN TRUE;
    END IF;

    FOREACH reserved_brand IN ARRAY reserved_brands LOOP
        FOREACH reserved_role IN ARRAY reserved_roles LOOP
            IF canonical_username = reserved_brand || '_' || reserved_role
                OR canonical_username = reserved_role || '_' || reserved_brand
            THEN
                RETURN TRUE;
            END IF;
        END LOOP;
    END LOOP;

    RETURN FALSE;
END;
$$;

-- Process profiles in a stable lock order so build_unique_public_username sees
-- every replacement chosen earlier in this migration. Use the existing neutral
-- default-alias generator rather than preserving an official-looking reserved
-- prefix such as admin_* or security_*.
DO $migration$
DECLARE
    reserved_profile RECORD;
    replacement_username TEXT;
BEGIN
    FOR reserved_profile IN
        SELECT app_user.id
        FROM public.users AS app_user
        WHERE public.is_reserved_public_username(app_user.public_username)
        ORDER BY app_user.id
        FOR UPDATE OF app_user
    LOOP
        replacement_username := public.build_unique_public_username(
            public.build_default_public_username(reserved_profile.id),
            reserved_profile.id
        );

        UPDATE public.users AS app_user
        SET
            public_username = replacement_username,
            public_author_name = CASE
                WHEN app_user.public_identity_source = 'alias'
                    THEN replacement_username
                ELSE app_user.public_author_name
            END
        WHERE app_user.id = reserved_profile.id;
    END LOOP;
END;
$migration$;

-- Rebuild and validate the profile's function-backed CHECK constraint.
-- PostgreSQL does not automatically recheck existing rows when an IMMUTABLE
-- function used by a validated CHECK constraint changes definition.
ALTER TABLE public.users
    ADD CONSTRAINT users_public_username_expanded_policy_check
    CHECK (public.is_valid_public_username(public_username)) NOT VALID;

ALTER TABLE public.users
    VALIDATE CONSTRAINT users_public_username_expanded_policy_check;

ALTER TABLE public.users
    DROP CONSTRAINT users_public_username_valid_check;

ALTER TABLE public.users
    RENAME CONSTRAINT users_public_username_expanded_policy_check
    TO users_public_username_valid_check;

-- mention_username is the historical token that still appears in the immutable
-- plain-text comment body. Keep its structural validation, but do not apply the
-- current reservation list or old mentions would stop matching rendered text.
ALTER TABLE public.explore_comment_mentions
    ADD CONSTRAINT explore_comment_mentions_username_expanded_policy_check
    CHECK (
        mention_username = pg_catalog.LOWER(mention_username)
        AND pg_catalog.CHAR_LENGTH(mention_username) BETWEEN 3 AND 24
        AND mention_username ~ '^[a-z][a-z0-9_]*[a-z0-9]$'
        AND mention_username !~ '__'
    ) NOT VALID;

ALTER TABLE public.explore_comment_mentions
    VALIDATE CONSTRAINT explore_comment_mentions_username_expanded_policy_check;

ALTER TABLE public.explore_comment_mentions
    DROP CONSTRAINT explore_comment_mentions_username_valid_check;

ALTER TABLE public.explore_comment_mentions
    RENAME CONSTRAINT explore_comment_mentions_username_expanded_policy_check
    TO explore_comment_mentions_username_valid_check;

NOTIFY pgrst, 'reload schema';

RESET statement_timeout;
RESET lock_timeout;
