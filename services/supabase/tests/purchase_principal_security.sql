\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(1);

DO $acl$
BEGIN
  IF has_table_privilege(
    'service_role',
    'internal.purchase_principals',
    'SELECT'
  ) OR has_table_privilege(
    'authenticated',
    'internal.purchase_principal_bindings',
    'SELECT'
  ) OR has_table_privilege(
    'anon',
    'internal.account_access_grants',
    'SELECT'
  ) THEN
    RAISE EXCEPTION 'purchase identity tables are directly exposed';
  END IF;

  IF NOT has_function_privilege(
    'service_role',
    'public.begin_purchase_principal_resolution(uuid,text,integer,bigint)',
    'EXECUTE'
  ) OR NOT has_function_privilege(
    'service_role',
    'public.complete_purchase_principal_resolution(uuid,uuid,text,bigint,bigint,text,timestamptz,boolean,text,timestamptz)',
    'EXECUTE'
  ) OR has_function_privilege(
    'authenticated',
    'public.begin_purchase_principal_resolution(uuid,text,integer,bigint)',
    'EXECUTE'
  ) OR has_function_privilege(
    'anon',
    'public.complete_purchase_principal_resolution(uuid,uuid,text,bigint,bigint,text,timestamptz,boolean,text,timestamptz)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'purchase identity resolver has an unsafe ACL';
  END IF;
END;
$acl$;

INSERT INTO auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  email_confirmed_at,
  last_sign_in_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at,
  is_anonymous
)
SELECT
  '00000000-0000-0000-0000-000000000000'::UUID,
  seed.user_id,
  'authenticated',
  'authenticated',
  seed.email,
  NOW(),
  NOW(),
  CASE
    WHEN seed.is_anonymous THEN
      jsonb_build_object('provider', 'anonymous', 'providers', '[]'::JSONB)
    ELSE
      jsonb_build_object(
        'provider',
        'google',
        'providers',
        jsonb_build_array('google')
      )
  END,
  '{}'::JSONB,
  NOW(),
  NOW(),
  seed.is_anonymous
FROM (VALUES
  (
    '21000000-0000-4000-8000-000000000001'::UUID,
    'principal-owner@naturebook.invalid',
    FALSE
  ),
  (
    '21000000-0000-4000-8000-000000000002'::UUID,
    'principal-anonymous@naturebook.invalid',
    TRUE
  ),
  (
    '21000000-0000-4000-8000-000000000003'::UUID,
    'principal-second-account@naturebook.invalid',
    FALSE
  )
) AS seed(user_id, email, is_anonymous);

INSERT INTO public.users (
  id,
  email,
  public_username,
  public_author_name,
  public_identity_source,
  subscription_tier,
  subscription_expires_at
)
VALUES
  (
    '21000000-0000-4000-8000-000000000001',
    'principal-owner@naturebook.invalid',
    'principal_owner_01',
    'Principal Owner',
    'alias',
    'free',
    NULL
  ),
  (
    '21000000-0000-4000-8000-000000000002',
    'principal-anonymous@naturebook.invalid',
    'principal_anonymous_02',
    'Principal Anonymous',
    'alias',
    'free',
    NULL
  ),
  (
    '21000000-0000-4000-8000-000000000003',
    'principal-second-account@naturebook.invalid',
    'principal_second_03',
    'Principal Second',
    'alias',
    'free',
    NULL
  )
ON CONFLICT (id) DO UPDATE
SET email = EXCLUDED.email,
    public_username = EXCLUDED.public_username,
    public_author_name = EXCLUDED.public_author_name,
    public_identity_source = EXCLUDED.public_identity_source,
    subscription_tier = EXCLUDED.subscription_tier,
    subscription_expires_at = EXCLUDED.subscription_expires_at;

UPDATE internal.purchase_identity_rollout_config
SET principal_mode = 'stable',
    account_grant_mode = 'dual_read',
    updated_at = CLOCK_TIMESTAMP()
WHERE config_key = 'current';

-- Exercise the exact previous-bundle writer before adoption. Stable
-- completion must retire this compatibility input for the adopted UUID.
SET LOCAL ROLE service_role;
DO $legacy_webhook_before_adoption$
BEGIN
  PERFORM public.apply_revenuecat_customer_state(
    'legacy-webhook-before-stable-adoption',
    1000,
    'RENEWAL',
    REPEAT('e', 64),
    1,
    JSONB_BUILD_ARRAY(
      JSONB_BUILD_OBJECT(
        'subject_kind', 'customer',
        'candidate_user_ids',
          JSONB_BUILD_ARRAY('21000000-0000-4000-8000-000000000001'),
        'authoritative_snapshot_at_ms', 1000,
        'target_tier', 'pro',
        'target_expires_at', NULL
      )
    )
  );
END;
$legacy_webhook_before_adoption$;
RESET ROLE;

CREATE TEMP TABLE purchase_principal_resolution_fixture (
  resolution_mode TEXT NOT NULL,
  purchase_principal_id UUID,
  revenuecat_app_user_id TEXT,
  minimum_client_protocol INTEGER NOT NULL,
  requires_attestation BOOLEAN NOT NULL,
  binding_intent_generation BIGINT,
  allow_non_subscription_pass_grant BOOLEAN
);
CREATE TEMP TABLE purchase_principal_binding_fixture (
  auth_user_id UUID NOT NULL,
  purchase_principal_id UUID NOT NULL,
  revenuecat_app_user_id TEXT NOT NULL,
  binding_generation BIGINT NOT NULL,
  account_grants_allowed BOOLEAN NOT NULL,
  already_bound BOOLEAN NOT NULL
);
GRANT SELECT, INSERT ON purchase_principal_resolution_fixture TO service_role;
GRANT SELECT, INSERT ON purchase_principal_binding_fixture TO service_role;

SET LOCAL ROLE service_role;
INSERT INTO purchase_principal_resolution_fixture
SELECT *
FROM public.begin_purchase_principal_resolution(
  '21000000-0000-4000-8000-000000000001',
  REPEAT('a', 64),
  1,
  1
);

DO $first_resolution$
DECLARE
  resolved purchase_principal_resolution_fixture%ROWTYPE;
BEGIN
  SELECT * INTO STRICT resolved
  FROM purchase_principal_resolution_fixture;
  IF resolved.resolution_mode <> 'stable'
     OR resolved.revenuecat_app_user_id <>
       '21000000-0000-4000-8000-000000000001'
     OR resolved.requires_attestation IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION 'first stable resolution did not adopt the existing customer';
  END IF;
END;
$first_resolution$;

INSERT INTO purchase_principal_binding_fixture
SELECT
  '21000000-0000-4000-8000-000000000001'::UUID,
  receipt.*
FROM public.complete_purchase_principal_resolution(
  '21000000-0000-4000-8000-000000000001',
  (SELECT purchase_principal_id FROM purchase_principal_resolution_fixture),
  REPEAT('a', 64),
  1,
  (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT,
  'pro',
  NOW() + INTERVAL '1 year',
  FALSE,
  'pro',
  NOW() + INTERVAL '30 days'
) AS receipt;
RESET ROLE;

DO $first_binding$
DECLARE
  owner_tier public.subscription_tier_enum;
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM internal.purchase_principal_bindings AS binding
    WHERE binding.purchase_principal_id = (
      SELECT purchase_principal_id
      FROM purchase_principal_resolution_fixture
    )
      AND binding.auth_user_id =
        '21000000-0000-4000-8000-000000000001'
  ) THEN
    RAISE EXCEPTION 'principal was not bound to its first Auth session';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM internal.account_access_grants AS grant_row
    WHERE grant_row.account_user_id =
        '21000000-0000-4000-8000-000000000001'
      AND grant_row.source_kind = 'revenuecat_legacy'
      AND grant_row.revoked_at IS NULL
  ) THEN
    RAISE EXCEPTION 'promotional state was not imported to the account ledger';
  END IF;
  SELECT subscription_tier INTO STRICT owner_tier
  FROM public.users
  WHERE id = '21000000-0000-4000-8000-000000000001';
  IF owner_tier <> 'pro'::public.subscription_tier_enum THEN
    RAISE EXCEPTION 'first effective entitlement was not projected';
  END IF;
  IF EXISTS (
    SELECT 1
    FROM internal.legacy_revenuecat_entitlement_state AS legacy
    WHERE legacy.merian_user_id =
      '21000000-0000-4000-8000-000000000001'
  ) THEN
    RAISE EXCEPTION 'stable adoption retained its legacy provider input';
  END IF;
END;
$first_binding$;

-- A previous webhook bundle cannot reinterpret an adopted UUID customer as
-- legacy combined access after that customer becomes a stable principal.
SET LOCAL ROLE service_role;
DO $legacy_webhook_stable_conflict$
BEGIN
  BEGIN
    PERFORM public.apply_revenuecat_customer_state(
      'legacy-webhook-stable-conflict',
      1000,
      'RENEWAL',
      REPEAT('f', 64),
      1,
      JSONB_BUILD_ARRAY(
        JSONB_BUILD_OBJECT(
          'subject_kind', 'customer',
          'candidate_user_ids',
            JSONB_BUILD_ARRAY('21000000-0000-4000-8000-000000000001'),
          'authoritative_snapshot_at_ms', 1000,
          'target_tier', 'pro',
          'target_expires_at', NULL
        )
      )
    );
    RAISE EXCEPTION
      'legacy webhook reinterpreted an active stable purchase principal';
  EXCEPTION
    WHEN SQLSTATE '55000' THEN
      IF SQLERRM <> 'revenuecat_legacy_identity_conflict' THEN
        RAISE;
      END IF;
  END;

  BEGIN
    PERFORM public.schedule_revenuecat_reconciliation(
      JSONB_BUILD_ARRAY(
        JSONB_BUILD_OBJECT(
          'subject_kind', 'customer',
          'lookup_app_user_id',
            '21000000-0000-4000-8000-000000000001',
          'candidate_user_ids',
            JSONB_BUILD_ARRAY('21000000-0000-4000-8000-000000000001')
        )
      )
    );
    RAISE EXCEPTION
      'legacy scheduler recreated a stable principal reconciliation lane';
  EXCEPTION
    WHEN SQLSTATE '55000' THEN
      IF SQLERRM <> 'revenuecat_legacy_identity_conflict' THEN
        RAISE;
      END IF;
  END;
END;
$legacy_webhook_stable_conflict$;
RESET ROLE;

DO $legacy_compatibility_not_recreated$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM internal.legacy_revenuecat_entitlement_state AS legacy
    WHERE legacy.merian_user_id =
      '21000000-0000-4000-8000-000000000001'
  ) OR EXISTS (
    SELECT 1
    FROM internal.revenuecat_reconciliation_queue AS queue
    WHERE queue.merian_user_id =
      '21000000-0000-4000-8000-000000000001'
  ) THEN
    RAISE EXCEPTION
      'previous webhook bundle recreated legacy state after stable adoption';
  END IF;
END;
$legacy_compatibility_not_recreated$;

-- The same device capability moves only StoreKit access to the anonymous
-- session. The imported promotional grant remains on its original account.
SET LOCAL ROLE service_role;
DO $same_capability$
DECLARE
  resolved RECORD;
BEGIN
  SELECT * INTO STRICT resolved
  FROM public.begin_purchase_principal_resolution(
    '21000000-0000-4000-8000-000000000002',
    REPEAT('a', 64),
    1,
    2
  );
  IF resolved.purchase_principal_id <> (
      SELECT purchase_principal_id
      FROM purchase_principal_resolution_fixture
    ) OR resolved.revenuecat_app_user_id <>
      '21000000-0000-4000-8000-000000000001' THEN
    RAISE EXCEPTION 'same capability did not resolve the same principal';
  END IF;
END;
$same_capability$;

DO $stale_binding_intent$
BEGIN
  BEGIN
    PERFORM *
    FROM public.complete_purchase_principal_resolution(
      '21000000-0000-4000-8000-000000000001',
      (SELECT purchase_principal_id FROM purchase_principal_resolution_fixture),
      REPEAT('a', 64),
      1,
      (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT,
      'pro',
      NOW() + INTERVAL '1 year',
      FALSE,
      'free',
      NULL
    );
    RAISE EXCEPTION
      'stale binding intent was allowed to overwrite a newer Auth session';
  EXCEPTION
    WHEN serialization_failure THEN
      IF SQLERRM <> 'purchase_principal_binding_intent_stale' THEN
        RAISE;
      END IF;
  END;
END;
$stale_binding_intent$;

INSERT INTO purchase_principal_binding_fixture
SELECT
  '21000000-0000-4000-8000-000000000002'::UUID,
  receipt.*
FROM public.complete_purchase_principal_resolution(
  '21000000-0000-4000-8000-000000000002',
  (SELECT purchase_principal_id FROM purchase_principal_resolution_fixture),
  REPEAT('a', 64),
  2,
  (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT + 1,
  'pro',
  NOW() + INTERVAL '1 year',
  FALSE,
  'pro',
  NOW() + INTERVAL '30 days'
) AS receipt;
RESET ROLE;

DO $anonymous_binding$
DECLARE
  owner_tier public.subscription_tier_enum;
  anonymous_tier public.subscription_tier_enum;
BEGIN
  IF EXISTS (
    SELECT 1
    FROM purchase_principal_binding_fixture
    WHERE auth_user_id = '21000000-0000-4000-8000-000000000002'
      AND account_grants_allowed
  ) THEN
    RAISE EXCEPTION 'anonymous session was allowed to consume account grants';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM internal.account_access_grants
    WHERE account_user_id = '21000000-0000-4000-8000-000000000001'
      AND revoked_at IS NULL
  ) THEN
    RAISE EXCEPTION 'account promotion followed the anonymous binding';
  END IF;
  SELECT subscription_tier INTO STRICT owner_tier
  FROM public.users
  WHERE id = '21000000-0000-4000-8000-000000000001';
  SELECT subscription_tier INTO STRICT anonymous_tier
  FROM public.users
  WHERE id = '21000000-0000-4000-8000-000000000002';
  IF owner_tier <> 'pro'::public.subscription_tier_enum
     OR anonymous_tier <> 'pro'::public.subscription_tier_enum THEN
    RAISE EXCEPTION 'account grant and StoreKit projections were not separated';
  END IF;
END;
$anonymous_binding$;

-- Provider transfers move StoreKit identity only. Even if CustomerInfo loses
-- the promotion at the source and reports it at the destination, the private
-- account-owned grant must remain unchanged.
SET LOCAL ROLE service_role;
DO $duplicate_transfer_identity$
BEGIN
  BEGIN
    PERFORM *
    FROM public.apply_revenuecat_identity_state(
      'purchase-principal-duplicate-transfer-identity-test',
      (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT + 5,
      'TRANSFER',
      REPEAT('4', 64),
      EXTRACT(EPOCH FROM NOW())::BIGINT,
      jsonb_build_array(
        jsonb_build_object(
          'subject_kind', 'transfer_source',
          'lookup_app_user_id',
            (SELECT revenuecat_app_user_id
             FROM purchase_principal_resolution_fixture),
          'identity_kind', 'purchase_principal',
          'identity_id',
            (SELECT purchase_principal_id
             FROM purchase_principal_resolution_fixture),
          'authoritative_snapshot_at_ms',
            (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT + 5,
          'target_store_tier', 'pro',
          'target_store_expires_at', NOW() + INTERVAL '1 year',
          'target_account_grant_tier', 'free',
          'target_account_grant_expires_at', NULL,
          'allow_non_subscription_pass_grant', FALSE
        ),
        jsonb_build_object(
          'subject_kind', 'transfer_destination',
          'lookup_app_user_id',
            (SELECT revenuecat_app_user_id
             FROM purchase_principal_resolution_fixture),
          'identity_kind', 'purchase_principal',
          'identity_id',
            (SELECT purchase_principal_id
             FROM purchase_principal_resolution_fixture),
          'authoritative_snapshot_at_ms',
            (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT + 5,
          'target_store_tier', 'pro',
          'target_store_expires_at', NOW() + INTERVAL '1 year',
          'target_account_grant_tier', 'free',
          'target_account_grant_expires_at', NULL,
          'allow_non_subscription_pass_grant', NULL
        )
      )
    );
    RAISE EXCEPTION 'one principal was accepted as both transfer sides';
  EXCEPTION
    WHEN raise_exception THEN
      IF SQLERRM <> 'revenuecat_identity_mapping_ambiguous' THEN
        RAISE;
      END IF;
  END;
END;
$duplicate_transfer_identity$;
RESET ROLE;

CREATE TEMP TABLE purchase_principal_grant_before_transfer ON COMMIT DROP AS
SELECT id, account_user_id, expires_at, revoked_at
FROM internal.account_access_grants
WHERE source_kind = 'revenuecat_legacy';

SET LOCAL ROLE service_role;
SELECT *
FROM public.apply_revenuecat_identity_state(
  'purchase-principal-transfer-source-grant-test',
  (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT + 10,
  'TRANSFER',
  REPEAT('8', 64),
  EXTRACT(EPOCH FROM NOW())::BIGINT,
  jsonb_build_array(
    jsonb_build_object(
      'subject_kind', 'transfer_source',
      'lookup_app_user_id',
        (SELECT revenuecat_app_user_id
         FROM purchase_principal_resolution_fixture),
      'identity_kind', 'purchase_principal',
      'identity_id',
        (SELECT purchase_principal_id
         FROM purchase_principal_resolution_fixture),
      'authoritative_snapshot_at_ms',
        (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT + 10,
      'target_store_tier', 'pro',
      'target_store_expires_at', NOW() + INTERVAL '1 year',
      'target_account_grant_tier', 'free',
      'target_account_grant_expires_at', NULL,
      'allow_non_subscription_pass_grant', FALSE
    )
  )
);
SELECT *
FROM public.apply_revenuecat_identity_state(
  'purchase-principal-transfer-destination-grant-test',
  (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT + 20,
  'TRANSFER',
  REPEAT('9', 64),
  EXTRACT(EPOCH FROM NOW())::BIGINT,
  jsonb_build_array(
    jsonb_build_object(
      'subject_kind', 'transfer_destination',
      'lookup_app_user_id',
        (SELECT revenuecat_app_user_id
         FROM purchase_principal_resolution_fixture),
      'identity_kind', 'purchase_principal',
      'identity_id',
        (SELECT purchase_principal_id
         FROM purchase_principal_resolution_fixture),
      'authoritative_snapshot_at_ms',
        (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT + 20,
      'target_store_tier', 'pro',
      'target_store_expires_at', NOW() + INTERVAL '1 year',
      'target_account_grant_tier', 'pro',
      'target_account_grant_expires_at', NOW() + INTERVAL '1 year',
      'allow_non_subscription_pass_grant', NULL
    )
  )
);
SELECT *
FROM public.apply_revenuecat_identity_state(
  'purchase-principal-post-transfer-grant-test',
  (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT + 25,
  'RENEWAL',
  REPEAT('7', 64),
  EXTRACT(EPOCH FROM NOW())::BIGINT,
  jsonb_build_array(
    jsonb_build_object(
      'subject_kind', 'customer',
      'lookup_app_user_id',
        (SELECT revenuecat_app_user_id
         FROM purchase_principal_resolution_fixture),
      'identity_kind', 'purchase_principal',
      'identity_id',
        (SELECT purchase_principal_id
         FROM purchase_principal_resolution_fixture),
      'authoritative_snapshot_at_ms',
        (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT + 25,
      'target_store_tier', 'pro',
      'target_store_expires_at', NOW() + INTERVAL '1 year',
      'target_account_grant_tier', 'pro',
      'target_account_grant_expires_at', NOW() + INTERVAL '2 years',
      'allow_non_subscription_pass_grant', NULL
    )
  )
);
SELECT *
FROM public.apply_revenuecat_identity_state(
  'purchase-principal-newer-snapshot-ordering-test',
  1,
  'RENEWAL',
  REPEAT('6', 64),
  1,
  jsonb_build_array(
    jsonb_build_object(
      'subject_kind', 'customer',
      'lookup_app_user_id',
        (SELECT revenuecat_app_user_id
         FROM purchase_principal_resolution_fixture),
      'identity_kind', 'purchase_principal',
      'identity_id',
        (SELECT purchase_principal_id
         FROM purchase_principal_resolution_fixture),
      'authoritative_snapshot_at_ms',
        (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT + 26,
      'target_store_tier', 'pro',
      'target_store_expires_at', NOW() + INTERVAL '18 months',
      'target_account_grant_tier', 'free',
      'target_account_grant_expires_at', NULL,
      'allow_non_subscription_pass_grant', NULL
    )
  )
);
SELECT *
FROM public.apply_revenuecat_identity_state(
  'purchase-principal-older-snapshot-ordering-test',
  (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT + 100,
  'EXPIRATION',
  REPEAT('5', 64),
  EXTRACT(EPOCH FROM NOW())::BIGINT,
  jsonb_build_array(
    jsonb_build_object(
      'subject_kind', 'customer',
      'lookup_app_user_id',
        (SELECT revenuecat_app_user_id
         FROM purchase_principal_resolution_fixture),
      'identity_kind', 'purchase_principal',
      'identity_id',
        (SELECT purchase_principal_id
         FROM purchase_principal_resolution_fixture),
      'authoritative_snapshot_at_ms',
        (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT + 24,
      'target_store_tier', 'free',
      'target_store_expires_at', NULL,
      'target_account_grant_tier', 'free',
      'target_account_grant_expires_at', NULL,
      'allow_non_subscription_pass_grant', NULL
    )
  )
);
SELECT *
FROM public.complete_purchase_principal_resolution(
  '21000000-0000-4000-8000-000000000002',
  (SELECT purchase_principal_id FROM purchase_principal_resolution_fixture),
  REPEAT('a', 64),
  2,
  (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT + 30,
  'pro',
  NOW() + INTERVAL '1 year',
  FALSE,
  'free',
  NULL
);
RESET ROLE;

DO $transfer_preserves_account_grant$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM purchase_principal_grant_before_transfer AS before_transfer
    FULL JOIN internal.account_access_grants AS after_transfer
      ON after_transfer.id = before_transfer.id
    WHERE before_transfer.id IS NULL
       OR after_transfer.id IS NULL
       OR after_transfer.account_user_id IS DISTINCT FROM
            before_transfer.account_user_id
       OR after_transfer.expires_at IS DISTINCT FROM
            before_transfer.expires_at
       OR after_transfer.revoked_at IS DISTINCT FROM
            before_transfer.revoked_at
  ) THEN
    RAISE EXCEPTION
      'provider transfer moved, extended, revoked, or created an account grant';
  END IF;
  IF (
    SELECT COUNT(*)
    FROM internal.purchase_principal_webhook_event_subjects
    WHERE event_id IN (
      'purchase-principal-transfer-source-grant-test',
      'purchase-principal-transfer-destination-grant-test',
      'purchase-principal-post-transfer-grant-test',
      'purchase-principal-newer-snapshot-ordering-test',
      'purchase-principal-older-snapshot-ordering-test'
    )
      AND account_grant_update_applied IS FALSE
  ) <> 5 THEN
    RAISE EXCEPTION
      'provider transfer grant freeze was not preserved or audited';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM internal.purchase_principal_webhook_event_subjects
    WHERE event_id = 'purchase-principal-newer-snapshot-ordering-test'
      AND outcome = 'applied'
  ) OR NOT EXISTS (
    SELECT 1
    FROM internal.purchase_principal_webhook_event_subjects
    WHERE event_id = 'purchase-principal-older-snapshot-ordering-test'
      AND outcome = 'stale'
  ) THEN
    RAISE EXCEPTION
      'authoritative snapshot ordering yielded to event delivery time';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM internal.purchase_principals AS principal
    WHERE principal.id = (
      SELECT purchase_principal_id
      FROM purchase_principal_resolution_fixture
    )
      AND principal.provider_account_grant_frozen
  ) THEN
    RAISE EXCEPTION 'provider transfer did not freeze later grant imports';
  END IF;
END;
$transfer_preserves_account_grant$;

-- After the account-grant cutover, promotional provider records are observed
-- but can no longer recreate or extend the compatibility grant.
UPDATE internal.purchase_identity_rollout_config
SET account_grant_mode = 'authoritative',
    updated_at = CLOCK_TIMESTAMP()
WHERE config_key = 'current';

SET LOCAL ROLE service_role;
SELECT *
FROM public.complete_purchase_principal_resolution(
  '21000000-0000-4000-8000-000000000002',
  (SELECT purchase_principal_id FROM purchase_principal_resolution_fixture),
  REPEAT('a', 64),
  2,
  (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT + 2,
  'pro',
  NOW() + INTERVAL '1 year',
  FALSE,
  'pro',
  NOW() + INTERVAL '30 days'
);
RESET ROLE;

DO $authoritative_cutover$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM internal.account_access_grants
    WHERE source_kind = 'revenuecat_legacy'
      AND revoked_at IS NULL
  ) THEN
    RAISE EXCEPTION 'authoritative cutover recreated a legacy provider grant';
  END IF;
  IF (SELECT subscription_tier FROM public.users
      WHERE id = '21000000-0000-4000-8000-000000000001') <>
      'free'::public.subscription_tier_enum THEN
    RAISE EXCEPTION 'retired compatibility grant remained projected';
  END IF;
END;
$authoritative_cutover$;

-- Operator grants remain account-scoped while StoreKit follows the stable
-- principal to another linked account.
SET LOCAL ROLE service_role;
SELECT public.record_account_access_grant(
  '21000000-0000-4000-8000-000000000001',
  'beta',
  NOW() + INTERVAL '90 days',
  REPEAT('c', 64)
);
SELECT *
FROM public.begin_purchase_principal_resolution(
  '21000000-0000-4000-8000-000000000003',
  REPEAT('a', 64),
  1,
  3
);
SELECT *
FROM public.complete_purchase_principal_resolution(
  '21000000-0000-4000-8000-000000000003',
  (SELECT purchase_principal_id FROM purchase_principal_resolution_fixture),
  REPEAT('a', 64),
  3,
  (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT + 3,
  'pro',
  NOW() + INTERVAL '1 year',
  FALSE,
  'pro',
  NOW() + INTERVAL '30 days'
);

DO $identity_resolver$
DECLARE
  resolved RECORD;
BEGIN
  SELECT * INTO STRICT resolved
  FROM public.resolve_revenuecat_identity_subjects(
    jsonb_build_array(
      jsonb_build_object(
        'subject_kind',
        'customer',
        'identifiers',
        jsonb_build_array(
          '21000000-0000-4000-8000-000000000001',
          '21000000-0000-4000-8000-000000000003'
        )
      )
    )
  );
  IF resolved.identity_kind <> 'purchase_principal'
     OR resolved.identity_id <> (
       SELECT purchase_principal_id
       FROM purchase_principal_resolution_fixture
     ) THEN
    RAISE EXCEPTION 'stable identity did not win before UUID fallback';
  END IF;
END;
$identity_resolver$;
RESET ROLE;

DO $account_switch$
BEGIN
  IF (SELECT subscription_tier FROM public.users
      WHERE id = '21000000-0000-4000-8000-000000000001') <>
      'pro'::public.subscription_tier_enum
     OR (SELECT subscription_tier FROM public.users
      WHERE id = '21000000-0000-4000-8000-000000000002') <>
      'free'::public.subscription_tier_enum
     OR (SELECT subscription_tier FROM public.users
      WHERE id = '21000000-0000-4000-8000-000000000003') <>
      'pro'::public.subscription_tier_enum THEN
    RAISE EXCEPTION 'account switch mixed StoreKit and account grant ownership';
  END IF;
END;
$account_switch$;

-- Account deletion and principal resolution share one fail-closed boundary.
-- A job that already exists rejects begin, and a job inserted after begin
-- rejects completion before any binding/provider projection can move.
INSERT INTO internal.account_deletion_jobs (user_id, status)
VALUES ('21000000-0000-4000-8000-000000000003', 'pending');

SET LOCAL ROLE service_role;
DO $deletion_blocks_resolution_begin$
BEGIN
  BEGIN
    PERFORM *
    FROM public.begin_purchase_principal_resolution(
      '21000000-0000-4000-8000-000000000003',
      REPEAT('a', 64),
      1,
      4
    );
    RAISE EXCEPTION 'active account deletion allowed principal begin';
  EXCEPTION
    WHEN no_data_found THEN
      IF SQLERRM <> 'purchase_principal_account_deletion_in_progress' THEN
        RAISE;
      END IF;
  END;
END;
$deletion_blocks_resolution_begin$;
RESET ROLE;

DELETE FROM internal.account_deletion_jobs
WHERE user_id = '21000000-0000-4000-8000-000000000003';

SET LOCAL ROLE service_role;
SELECT *
FROM public.begin_purchase_principal_resolution(
  '21000000-0000-4000-8000-000000000003',
  REPEAT('a', 64),
  1,
  4
);
RESET ROLE;

INSERT INTO internal.account_deletion_jobs (user_id, status)
VALUES ('21000000-0000-4000-8000-000000000003', 'pending');

SET LOCAL ROLE service_role;
DO $deletion_blocks_resolution_completion$
BEGIN
  BEGIN
    PERFORM *
    FROM public.complete_purchase_principal_resolution(
      '21000000-0000-4000-8000-000000000003',
      (SELECT purchase_principal_id
       FROM purchase_principal_resolution_fixture),
      REPEAT('a', 64),
      4,
      (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT + 4,
      'pro',
      NOW() + INTERVAL '1 year',
      FALSE,
      'free',
      NULL
    );
    RAISE EXCEPTION 'active account deletion allowed principal completion';
  EXCEPTION
    WHEN no_data_found THEN
      IF SQLERRM <> 'purchase_principal_account_deletion_in_progress' THEN
        RAISE;
      END IF;
  END;
END;
$deletion_blocks_resolution_completion$;
RESET ROLE;

DELETE FROM internal.account_deletion_jobs
WHERE user_id = '21000000-0000-4000-8000-000000000003';

-- A global rollback stops new adoption but cannot rotate an installation that
-- has already activated a stable RevenueCat customer. Its exact capability
-- remains stable and rebindable until a separately reviewed revocation.
UPDATE internal.purchase_identity_rollout_config
SET principal_mode = 'legacy',
    updated_at = CLOCK_TIMESTAMP()
WHERE config_key = 'current';

SET LOCAL ROLE service_role;
DO $rollback_existing_principal$
DECLARE
  resolved RECORD;
BEGIN
  SELECT * INTO STRICT resolved
  FROM public.begin_purchase_principal_resolution(
    '21000000-0000-4000-8000-000000000003',
    REPEAT('a', 64),
    1,
    5
  );
  IF resolved.resolution_mode <> 'stable'
     OR resolved.purchase_principal_id <> (
       SELECT purchase_principal_id
       FROM purchase_principal_resolution_fixture
     ) THEN
    RAISE EXCEPTION 'rollback rotated an activated purchase principal';
  END IF;
END;
$rollback_existing_principal$;

SELECT *
FROM public.complete_purchase_principal_resolution(
  '21000000-0000-4000-8000-000000000003',
  (SELECT purchase_principal_id FROM purchase_principal_resolution_fixture),
  REPEAT('a', 64),
  5,
  (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT + 4,
  'pro',
  NOW() + INTERVAL '1 year',
  FALSE,
  'free',
  NULL
);

DO $rollback_new_principal$
DECLARE
  resolved RECORD;
BEGIN
  SELECT * INTO STRICT resolved
  FROM public.begin_purchase_principal_resolution(
    '21000000-0000-4000-8000-000000000003',
    REPEAT('d', 64),
    1,
    1
  );
  IF resolved.resolution_mode <> 'legacy'
     OR resolved.purchase_principal_id IS NOT NULL THEN
    RAISE EXCEPTION 'rollback admitted a new purchase principal';
  END IF;
END;
$rollback_new_principal$;
RESET ROLE;

UPDATE internal.purchase_identity_rollout_config
SET principal_mode = 'stable',
    updated_at = CLOCK_TIMESTAMP()
WHERE config_key = 'current';

-- Aggregate health alerts only when an active StoreKit-bearing principal loses
-- its Auth binding. Free abandoned installations must not warn forever.
SET LOCAL ROLE service_role;
DO $bound_health$
DECLARE
  health RECORD;
BEGIN
  SELECT * INTO STRICT health
  FROM public.get_purchase_principal_health();
  IF health.unbound_active_principal_count <> 0 THEN
    RAISE EXCEPTION 'bound purchase principal was reported as unbound';
  END IF;
END;
$bound_health$;
RESET ROLE;

DELETE FROM internal.purchase_principal_bindings
WHERE purchase_principal_id = (
  SELECT purchase_principal_id FROM purchase_principal_resolution_fixture
);

SET LOCAL ROLE service_role;
DO $unbound_paid_health$
DECLARE
  health RECORD;
BEGIN
  SELECT * INTO STRICT health
  FROM public.get_purchase_principal_health();
  IF health.unbound_active_principal_count <> 1 THEN
    RAISE EXCEPTION 'unbound paid purchase principal was not reported';
  END IF;
END;
$unbound_paid_health$;
RESET ROLE;

UPDATE internal.purchase_principal_store_state
SET target_tier = 'free',
    target_expires_at = NULL,
    allow_non_subscription_pass_grant = TRUE,
    updated_at = CLOCK_TIMESTAMP()
WHERE purchase_principal_id = (
  SELECT purchase_principal_id FROM purchase_principal_resolution_fixture
);

SET LOCAL ROLE service_role;
-- NOW() is transaction-stable. Earlier fixture phases advanced the same
-- principal through a +30 ms snapshot, so this refund must use a strictly newer
-- synthetic timestamp or it correctly remains stale and cannot revoke the pass.
SELECT *
FROM public.apply_revenuecat_identity_state(
  'purchase-principal-pass-refund-test',
  (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT + 1000,
  'REFUND',
  REPEAT('f', 64),
  EXTRACT(EPOCH FROM NOW())::BIGINT,
  jsonb_build_array(
    jsonb_build_object(
      'subject_kind', 'customer',
      'lookup_app_user_id',
        (SELECT revenuecat_app_user_id
         FROM purchase_principal_resolution_fixture),
      'identity_kind', 'purchase_principal',
      'identity_id',
        (SELECT purchase_principal_id
         FROM purchase_principal_resolution_fixture),
      'authoritative_snapshot_at_ms',
        (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT + 1000,
      'target_store_tier', 'free',
      'target_store_expires_at', NULL,
      'target_account_grant_tier', 'free',
      'target_account_grant_expires_at', NULL,
      'allow_non_subscription_pass_grant', FALSE
    )
  )
);
SELECT public.schedule_revenuecat_identity_reconciliation(
  jsonb_build_array(
    jsonb_build_object(
      'subject_kind', 'customer',
      'lookup_app_user_id',
        (SELECT revenuecat_app_user_id
         FROM purchase_principal_resolution_fixture),
      'identity_kind', 'purchase_principal',
      'identity_id',
        (SELECT purchase_principal_id
         FROM purchase_principal_resolution_fixture)
    )
  )
);
DO $durable_pass_revocation$
DECLARE
  claim RECORD;
BEGIN
  SELECT * INTO STRICT claim
  FROM public.claim_purchase_principal_reconciliations(1);
  IF claim.allow_non_subscription_pass_grant IS DISTINCT FROM FALSE THEN
    RAISE EXCEPTION
      'refunded pass policy was not returned by reconciliation claim';
  END IF;
END;
$durable_pass_revocation$;
RESET ROLE;

DO $durable_pass_state$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM internal.purchase_principal_store_state AS state
    WHERE state.purchase_principal_id = (
      SELECT purchase_principal_id
      FROM purchase_principal_resolution_fixture
    )
      AND state.allow_non_subscription_pass_grant
  ) THEN
    RAISE EXCEPTION
      'refunded pass policy was not durable in principal state';
  END IF;
END;
$durable_pass_state$;

SET LOCAL ROLE service_role;
DO $unbound_free_health$
DECLARE
  health RECORD;
BEGIN
  SELECT * INTO STRICT health
  FROM public.get_purchase_principal_health();
  IF health.unbound_active_principal_count <> 0 THEN
    RAISE EXCEPTION 'unbound free purchase principal created a permanent alert';
  END IF;
END;
$unbound_free_health$;
RESET ROLE;

-- Private operational evidence remains useful after account deletion, but it
-- must not retain the deleted Auth UUID. Exercise both history and webhook
-- projection evidence before the transaction rolls back.
INSERT INTO internal.revenuecat_webhook_events (
  event_id,
  event_timestamp_ms,
  event_type,
  payload_sha256,
  signature_timestamp_s,
  outcome,
  subject_count,
  applied_count,
  stale_count
)
VALUES (
  'purchase-principal-delete-scrub-test',
  1,
  'TEST',
  REPEAT('e', 64),
  1,
  'applied',
  1,
  1,
  0
);

INSERT INTO internal.purchase_principal_webhook_event_subjects (
  event_id,
  purchase_principal_id,
  subject_kind,
  authoritative_snapshot_at_ms,
  target_store_tier,
  target_store_expires_at,
  target_account_grant_tier,
  target_account_grant_expires_at,
  account_grant_update_applied,
  outcome,
  projected_auth_user_id
)
VALUES (
  'purchase-principal-delete-scrub-test',
  (SELECT purchase_principal_id FROM purchase_principal_resolution_fixture),
  'customer',
  1,
  'free',
  NULL,
  'free',
  NULL,
  FALSE,
  'applied',
  '21000000-0000-4000-8000-000000000002'
);

INSERT INTO internal.purchase_principals (
  id,
  revenuecat_app_user_id,
  capability_hash,
  status,
  account_grant_owner_user_id,
  activated_at
)
VALUES (
  '21000000-0000-4000-8000-000000000099',
  'MERIAN_PP_ACCOUNT_DELETE_TEST',
  REPEAT('b', 64),
  'active',
  '21000000-0000-4000-8000-000000000002',
  CLOCK_TIMESTAMP()
);

INSERT INTO internal.purchase_principal_bindings (
  purchase_principal_id,
  auth_user_id
)
VALUES (
  '21000000-0000-4000-8000-000000000099',
  '21000000-0000-4000-8000-000000000002'
);

SELECT internal.prepare_purchase_principals_for_account_deletion(
  '21000000-0000-4000-8000-000000000002'
);

DO $account_deletion_detaches_principal$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM internal.purchase_principals AS principal
    WHERE principal.id = '21000000-0000-4000-8000-000000000099'
      AND principal.account_grant_owner_user_id IS NULL
      AND principal.provider_account_grant_frozen
  ) OR EXISTS (
    SELECT 1
    FROM internal.purchase_principal_bindings AS binding
    WHERE binding.auth_user_id =
      '21000000-0000-4000-8000-000000000002'
  ) THEN
    RAISE EXCEPTION
      'account deletion did not detach and freeze the stable principal';
  END IF;

  IF pg_catalog.STRPOS(
      pg_catalog.PG_GET_FUNCTIONDEF(
        'public.complete_account_deletion_cleanup(uuid,uuid)'::REGPROCEDURE
      ),
      'prepare_purchase_principals_for_account_deletion('
    ) = 0 THEN
    RAISE EXCEPTION
      'account deletion cleanup did not install the principal detach step';
  END IF;

  IF pg_catalog.STRPOS(
      pg_catalog.PG_GET_FUNCTIONDEF(
        'public.consume_ghost_profile_merge_handoff(uuid,text)'::REGPROCEDURE
      ),
      'lock_purchase_principals_for_auth_users('
    ) = 0 THEN
    RAISE EXCEPTION
      'guest merge did not install the principal-first lock step';
  END IF;
END;
$account_deletion_detaches_principal$;

DELETE FROM public.users
WHERE id = '21000000-0000-4000-8000-000000000002';

DO $deleted_identity_scrub$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM internal.purchase_principal_binding_history AS history
    WHERE history.previous_auth_user_id =
        '21000000-0000-4000-8000-000000000002'
       OR history.next_auth_user_id =
        '21000000-0000-4000-8000-000000000002'
  ) OR EXISTS (
    SELECT 1
    FROM internal.purchase_principal_webhook_event_subjects AS subject
    WHERE subject.projected_auth_user_id =
      '21000000-0000-4000-8000-000000000002'
  ) THEN
    RAISE EXCEPTION
      'deleted Auth UUID remained in purchase identity evidence';
  END IF;
END;
$deleted_identity_scrub$;

SELECT extensions.pass(
  'stable purchase principals preserve StoreKit continuity without moving account grants'
);
SELECT * FROM extensions.finish();
ROLLBACK;
