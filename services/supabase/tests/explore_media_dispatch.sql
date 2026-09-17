\set ON_ERROR_STOP on
-- Disposable catalog only: every pg_net request is rolled back before commit.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(13);

SELECT extensions.ok(
    (SELECT COUNT(*) = 1 AND BOOL_AND(schedule = '*/5 * * * *')
     FROM cron.job WHERE jobname = 'reconcile_explore_media_health_every_five_minutes'),
    'exactly one media-health job keeps the five-minute schedule'
);

-- Replace only the wall-clock dependency; execute the installed command, not a
-- copied predicate. URLs and credentials are synthetic and never leave this tx.
DELETE FROM vault.secrets WHERE name IN ('SUPABASE_URL', 'SUPABASE_SERVICE_ROLE_KEY');
SELECT vault.create_secret('https://example.invalid', 'SUPABASE_URL');
SELECT vault.create_secret('sb_' || 'secret_' || 'disposable_contract_fixture_only', 'SUPABASE_SERVICE_ROLE_KEY');

CREATE FUNCTION pg_temp.media_dispatches(at_time TIMESTAMPTZ)
RETURNS BIGINT LANGUAGE PLPGSQL AS $$
DECLARE
    job_command TEXT;
    before_count BIGINT;
    after_count BIGINT;
BEGIN
    SELECT command INTO STRICT job_command FROM cron.job
    WHERE jobname = 'reconcile_explore_media_health_every_five_minutes';
    IF pg_catalog.STRPOS(job_command, 'pg_catalog.CLOCK_TIMESTAMP()') = 0 THEN
        RAISE EXCEPTION 'installed dispatch clock seam missing';
    END IF;
    job_command := pg_catalog.REPLACE(job_command, 'pg_catalog.CLOCK_TIMESTAMP()',
        pg_catalog.QUOTE_LITERAL(at_time) || '::TIMESTAMPTZ');
    SELECT COUNT(*) INTO before_count FROM net.http_request_queue
    WHERE url = 'https://example.invalid/functions/v1/reconcile-explore-media-health';
    EXECUTE job_command;
    SELECT COUNT(*) INTO after_count FROM net.http_request_queue
    WHERE url = 'https://example.invalid/functions/v1/reconcile-explore-media-health';
    RETURN after_count - before_count;
END;
$$;

INSERT INTO auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    is_anonymous
)
VALUES (
    '00000000-0000-0000-0000-000000000000',
    '00000000-0000-4000-8000-00000000e901',
    'authenticated',
    'authenticated',
    'io-gate@naturebook.invalid',
    pg_catalog.NOW(),
    '{"provider":"email","providers":["email"]}'::JSONB,
    '{}'::JSONB,
    pg_catalog.NOW(),
    pg_catalog.NOW(),
    FALSE
);

INSERT INTO public.users (
    id,
    email,
    public_username,
    public_author_name,
    public_identity_source
)
VALUES (
    '00000000-0000-4000-8000-00000000e901',
    'io-gate@naturebook.invalid',
    'io_gate_e901',
    'Explore Media Health',
    'alias'
)
ON CONFLICT (id) DO UPDATE
SET email = EXCLUDED.email;

INSERT INTO public.species_dictionary (
    id,
    scientific_name,
    common_names,
    kingdom,
    phylum,
    class,
    "order",
    family,
    genus,
    native_region
)
VALUES (
    '00000000-0000-4000-8000-00000000e911',
    'Contractus mediaperditus',
    '{"en":"Media health contract species"}'::JSONB,
    'Animalia',
    'Chordata',
    'Aves',
    'Passeriformes',
    'Contractidae',
    'Contractus',
    'Test region'
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.scans (
    id,
    user_id,
    species_id,
    image_storage_urls,
    ai_confidence_score,
    geoprivacy
)
VALUES (
    '00000000-0000-4000-8000-00000000e921',
    '00000000-0000-4000-8000-00000000e901',
    '00000000-0000-4000-8000-00000000e911',
    ARRAY[
        'https://media.merian.app/public_uploads/free/00000000-0000-4000-8000-00000000e901/one.webp',
        'https://media.merian.app/public_uploads/free/00000000-0000-4000-8000-00000000e901/two.webp'
    ]::TEXT[],
    0.94,
    'obscured'
);


INSERT INTO public.explore_posts (id, user_id, scan_id, species_common_name, location_sharing, shared_at)
VALUES ('00000000-0000-4000-8000-00000000e931', '00000000-0000-4000-8000-00000000e901',
        '00000000-0000-4000-8000-00000000e921', 'Dispatch fixture', 'obscured', NOW());
INSERT INTO public.explore_post_media (id, post_id, kind, url, order_index)
VALUES ('00000000-0000-4000-8000-00000000e941', '00000000-0000-4000-8000-00000000e931',
        'image', 'https://media.merian.app/public_uploads/free/00000000-0000-4000-8000-00000000e901/one.webp', 0);
-- Isolate due work from any seed data, within this rolled-back fixture only.
UPDATE public.explore_post_media SET next_health_check_at = '2100-01-01';
SELECT extensions.is(pg_temp.media_dispatches('2001-01-01 00:05:00+00'), 0::BIGINT, 'idle alternate tick skips dispatch');
SELECT extensions.is(pg_temp.media_dispatches('2001-01-01 00:10:00+00'), 1::BIGINT, 'idle ten-minute heartbeat dispatches');
SELECT extensions.is(pg_temp.media_dispatches('2001-01-01 00:20:00.750+00'), 1::BIGINT, 'heartbeat is independent of prior audit start-time jitter');

UPDATE public.explore_post_media SET next_health_check_at = '2001-01-01 00:05:00+00'
WHERE id = '00000000-0000-4000-8000-00000000e941';
SELECT extensions.is(pg_temp.media_dispatches('2001-01-01 00:05:00+00'), 1::BIGINT, 'due-time equality dispatches on alternate tick');
INSERT INTO internal.explore_media_health_check_claims (media_id, claim_token, claimed_at, claimed_until)
VALUES ('00000000-0000-4000-8000-00000000e941', '00000000-0000-4000-8000-00000000e951',
        '2001-01-01 00:04:00+00', '2001-01-01 00:06:00+00');
SELECT extensions.is(pg_temp.media_dispatches('2001-01-01 00:05:00+00'), 0::BIGINT, 'active lease prevents needless dispatch');
UPDATE internal.explore_media_health_check_claims SET claimed_until = '2001-01-01 00:05:00+00'
WHERE media_id = '00000000-0000-4000-8000-00000000e941';
SELECT extensions.is(pg_temp.media_dispatches('2001-01-01 00:05:00+00'), 1::BIGINT, 'lease expiry equality makes work eligible');
SELECT extensions.ok(
    (SELECT claim_token = '00000000-0000-4000-8000-00000000e951' AND claimed_until = '2001-01-01 00:05:00+00'
     FROM internal.explore_media_health_check_claims WHERE media_id = '00000000-0000-4000-8000-00000000e941'),
    'dispatch precheck never claims or rewrites a lease'
);
UPDATE public.explore_posts SET unshared_at = NOW() WHERE id = '00000000-0000-4000-8000-00000000e931';
SELECT extensions.is(pg_temp.media_dispatches('2001-01-01 00:05:00+00'), 0::BIGINT, 'unpublished due media does not dispatch');
UPDATE public.explore_posts SET unshared_at = NULL, moderated_at = NOW() WHERE id = '00000000-0000-4000-8000-00000000e931';
SELECT extensions.is(pg_temp.media_dispatches('2001-01-01 00:05:00+00'), 0::BIGINT, 'moderated due media does not dispatch');
UPDATE public.explore_posts SET moderated_at = NULL WHERE id = '00000000-0000-4000-8000-00000000e931';
UPDATE public.scans SET is_tombstoned = TRUE WHERE id = '00000000-0000-4000-8000-00000000e921';
SELECT extensions.is(pg_temp.media_dispatches('2001-01-01 00:05:00+00'), 0::BIGINT, 'tombstoned scan does not dispatch');
SELECT extensions.ok(
    NOT EXISTS (SELECT 1 FROM net.http_request_queue
        WHERE url = 'https://example.invalid/functions/v1/reconcile-explore-media-health'
          AND (pg_catalog.CONVERT_FROM(body, 'UTF8')::JSONB IS DISTINCT FROM '{"limit":200,"leaseSeconds":300}'::JSONB
               OR timeout_milliseconds <> 120000 OR headers ? 'Authorization'
               OR NOT headers ? 'apikey')),
    'queued requests preserve payload, timeout, and opaque-key transport'
);
-- Invalid credentials would raise if the idle path reached the header helper.
DELETE FROM vault.secrets WHERE name = 'SUPABASE_SERVICE_ROLE_KEY';
SELECT pg_catalog.SET_CONFIG('app.settings.supabase_service_role_key', 'invalid-test-key', TRUE);
SELECT extensions.is(pg_temp.media_dispatches('2001-01-01 00:05:00+00'), 0::BIGINT, 'idle skip returns before credential transport');

SELECT * FROM extensions.finish();
ROLLBACK;
