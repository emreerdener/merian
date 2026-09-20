\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(8);

-- Replay the new forward migration against a pending fixture with real durable
-- usage. All fixture state, including the replayed DDL, rolls back at the end.
INSERT INTO auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data)
VALUES ('00000000-0000-4000-8000-00000000fcba', 'authenticated', 'authenticated',
    'field-chat-beta@naturebook.invalid', '{}', '{}');
INSERT INTO public.users (
    id, email, public_username, public_author_name, public_identity_source
) VALUES (
    '00000000-0000-4000-8000-00000000fcba', 'field-chat-beta@naturebook.invalid',
    'field_chat_beta', 'Beta Test', 'alias'
) ON CONFLICT (id) DO UPDATE SET
    public_username = EXCLUDED.public_username,
    public_author_name = EXCLUDED.public_author_name,
    public_identity_source = EXCLUDED.public_identity_source;
INSERT INTO internal.field_chat_daily_admissions (
    user_id, admission_day, admitted_count, first_admitted_at, last_admitted_at
) VALUES (
    '00000000-0000-4000-8000-00000000fcba',
    (CURRENT_TIMESTAMP AT TIME ZONE 'UTC')::DATE, 17,
    CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
);
ALTER TABLE internal.field_chat_admission_cutover
    DROP COLUMN beta_early_activation_at,
    DROP COLUMN beta_original_not_before_utc;
UPDATE internal.field_chat_admission_cutover
SET seeded_at = pg_catalog.CLOCK_TIMESTAMP() - INTERVAL '1 second',
    not_before_utc = pg_catalog.DATE_TRUNC('day', pg_catalog.CLOCK_TIMESTAMP(), 'UTC') + INTERVAL '1 day',
    activated_at = NULL, activated_candidate_sha = NULL,
    activated_migration_sha256 = NULL, activated_explore_bundle_sha256 = NULL,
    activated_insight_bundle_sha256 = NULL, activated_species_dictionary_bundle_sha256 = NULL;
CREATE TEMP TABLE beta_before AS SELECT
    not_before_utc AS original_boundary,
    (SELECT pg_catalog.JSONB_AGG(pg_catalog.TO_JSONB(a) ORDER BY a.user_id, a.admission_day)
        FROM internal.field_chat_daily_admissions AS a) AS admissions,
    pg_catalog.PG_GET_FUNCTIONDEF('public.activate_field_chat_admission_cutover(text,text,text,text,text)'::REGPROCEDURE) AS activation,
    pg_catalog.PG_GET_FUNCTIONDEF('public.reserve_field_chat_send(uuid,uuid,text,uuid,text,uuid)'::REGPROCEDURE) AS reservation
FROM internal.field_chat_admission_cutover;
\ir ../migrations/20260919125625_authorize_immediate_field_chat_beta_activation.sql
SELECT extensions.ok((SELECT
    c.beta_original_not_before_utc = b.original_boundary
    AND c.beta_early_activation_at = c.not_before_utc
    AND c.not_before_utc > c.seeded_at
    AND c.not_before_utc < b.original_boundary
    FROM internal.field_chat_admission_cutover c CROSS JOIN beta_before b),
    'pending beta eligibility is advanced with original boundary audit evidence');
SELECT extensions.ok((SELECT activated_at IS NULL AND not_before_utc <= pg_catalog.CLOCK_TIMESTAMP()
    FROM internal.field_chat_admission_cutover), 'eligibility does not activate admission');
SELECT extensions.ok((SELECT admissions = (SELECT pg_catalog.JSONB_AGG(pg_catalog.TO_JSONB(a) ORDER BY a.user_id, a.admission_day)
    FROM internal.field_chat_daily_admissions a) FROM beta_before), 'all durable usage remains unchanged');
SELECT extensions.ok((SELECT activation = pg_catalog.PG_GET_FUNCTIONDEF(
    'public.activate_field_chat_admission_cutover(text,text,text,text,text)'::REGPROCEDURE)
    FROM beta_before), 'service-only activation and all five identity checks remain unchanged');
SELECT extensions.ok((SELECT reservation = pg_catalog.PG_GET_FUNCTIONDEF(
    'public.reserve_field_chat_send(uuid,uuid,text,uuid,text,uuid)'::REGPROCEDURE)
    FROM beta_before), 'atomic quota and admission security remain unchanged');
SELECT extensions.ok(
    NOT pg_catalog.HAS_TABLE_PRIVILEGE('anon', 'internal.field_chat_admission_cutover', 'SELECT')
    AND NOT pg_catalog.HAS_TABLE_PRIVILEGE('authenticated', 'internal.field_chat_admission_cutover', 'SELECT')
    AND NOT pg_catalog.HAS_TABLE_PRIVILEGE('service_role', 'internal.field_chat_admission_cutover', 'UPDATE'),
    'beta evidence grants no additional API access');

-- Already-active installations must retain exact activation identities.
UPDATE internal.field_chat_admission_cutover
SET activated_at = pg_catalog.CLOCK_TIMESTAMP(),
    activated_candidate_sha = pg_catalog.REPEAT('a', 40),
    activated_migration_sha256 = pg_catalog.REPEAT('b', 64),
    activated_explore_bundle_sha256 = pg_catalog.REPEAT('c', 64),
    activated_insight_bundle_sha256 = pg_catalog.REPEAT('d', 64),
    activated_species_dictionary_bundle_sha256 = pg_catalog.REPEAT('e', 64);
ALTER TABLE internal.field_chat_admission_cutover
    DROP COLUMN beta_early_activation_at,
    DROP COLUMN beta_original_not_before_utc;
CREATE TEMP TABLE beta_active_before AS SELECT pg_catalog.TO_JSONB(c) AS state
    FROM internal.field_chat_admission_cutover c;
\ir ../migrations/20260919125625_authorize_immediate_field_chat_beta_activation.sql
SELECT extensions.ok((SELECT
    (pg_catalog.TO_JSONB(c) - 'beta_early_activation_at' - 'beta_original_not_before_utc') = b.state
    FROM internal.field_chat_admission_cutover c CROSS JOIN beta_active_before b),
    'active installation retains original eligibility and activation evidence');
SELECT extensions.ok((SELECT beta_early_activation_at IS NULL AND beta_original_not_before_utc IS NULL
    FROM internal.field_chat_admission_cutover), 'active installation receives no beta exception');
SELECT * FROM extensions.finish();
ROLLBACK;
