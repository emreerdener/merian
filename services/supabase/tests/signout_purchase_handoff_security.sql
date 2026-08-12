\set ON_ERROR_STOP on

BEGIN;
SELECT extensions.plan(1);

DO $$
BEGIN
  IF has_table_privilege(
    'authenticated',
    'internal.signout_purchase_handoffs',
    'SELECT'
  ) OR has_table_privilege(
    'service_role',
    'internal.signout_purchase_handoffs',
    'SELECT'
  ) THEN
    RAISE EXCEPTION
      'an API role unexpectedly has direct sign-out handoff access';
  END IF;

  IF has_function_privilege(
    'anon',
    'public.bind_signout_purchase_handoff(uuid,text)',
    'EXECUTE'
  ) OR has_function_privilege(
    'authenticated',
    'public.issue_signout_purchase_handoff(uuid,text,bigint,text,timestamptz)',
    'EXECUTE'
  ) OR has_function_privilege(
    'authenticated',
    'public.claim_revenuecat_reconciliation_for_user(uuid)',
    'EXECUTE'
  ) OR has_function_privilege(
    'authenticated',
    'public.complete_signout_purchase_handoff(uuid,text,uuid,bigint,text,timestamptz)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'sign-out handoff grants exceed their reviewed roles';
  END IF;

  IF NOT has_function_privilege(
    'service_role',
    'public.issue_signout_purchase_handoff(uuid,text,bigint,text,timestamptz)',
    'EXECUTE'
  ) OR NOT has_function_privilege(
    'authenticated',
    'public.bind_signout_purchase_handoff(uuid,text)',
    'EXECUTE'
  ) OR NOT has_function_privilege(
    'authenticated',
    'public.cancel_signout_purchase_handoff(uuid,text)',
    'EXECUTE'
  ) OR NOT has_function_privilege(
    'service_role',
    'public.complete_signout_purchase_handoff(uuid,text,uuid,bigint,text,timestamptz)',
    'EXECUTE'
  ) OR NOT has_function_privilege(
    'service_role',
    'public.claim_revenuecat_reconciliation_for_user(uuid)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'sign-out handoff is missing a reviewed RPC grant';
  END IF;
END;
$$;

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
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::UUID,
    'signout-source@naturebook.invalid',
    FALSE
  ),
  (
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2'::UUID,
    'signout-destination@naturebook.invalid',
    TRUE
  ),
  (
    'cccccccc-cccc-4ccc-8ccc-ccccccccccc3'::UUID,
    'signout-second-destination@naturebook.invalid',
    TRUE
  ),
  (
    'dddddddd-dddd-4ddd-8ddd-ddddddddddd4'::UUID,
    'signout-linked-attacker@naturebook.invalid',
    FALSE
  ),
  (
    'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee5'::UUID,
    'signout-stale-anonymous@naturebook.invalid',
    TRUE
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
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
    'signout-source@naturebook.invalid',
    'signout_source_a1',
    'Signout Source',
    'alias',
    'pro',
    NOW() + INTERVAL '1 year'
  ),
  (
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2',
    'signout-destination@naturebook.invalid',
    'signout_destination_b2',
    'Signout Destination',
    'alias',
    'free',
    NULL
  ),
  (
    'cccccccc-cccc-4ccc-8ccc-ccccccccccc3',
    'signout-second-destination@naturebook.invalid',
    'signout_second_c3',
    'Signout Second',
    'alias',
    'free',
    NULL
  ),
  (
    'dddddddd-dddd-4ddd-8ddd-ddddddddddd4',
    'signout-linked-attacker@naturebook.invalid',
    'signout_attacker_d4',
    'Signout Attacker',
    'alias',
    'free',
    NULL
  ),
  (
    'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee5',
    'signout-stale-anonymous@naturebook.invalid',
    'signout_stale_e5',
    'Signout Stale',
    'alias',
    'free',
    NULL
  )
ON CONFLICT (id) DO UPDATE
SET email = EXCLUDED.email,
    public_username = EXCLUDED.public_username,
    subscription_tier = EXCLUDED.subscription_tier,
    subscription_expires_at = EXCLUDED.subscription_expires_at;

CREATE TEMP TABLE signout_cancel_fixture (
  handoff_id UUID NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL
);
CREATE TEMP TABLE signout_transfer_fixture (
  handoff_id UUID NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  destination_snapshot_at_ms BIGINT NOT NULL DEFAULT
    ((EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT)
);
CREATE TEMP TABLE signout_deletion_race_fixture (
  handoff_id UUID NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL
);
GRANT SELECT, INSERT ON signout_cancel_fixture
  TO authenticated, service_role;
GRANT SELECT, INSERT ON signout_transfer_fixture
  TO authenticated, service_role;
GRANT SELECT, INSERT ON signout_deletion_race_fixture
  TO authenticated, service_role;

SET LOCAL ROLE service_role;
INSERT INTO signout_cancel_fixture
SELECT *
FROM public.issue_signout_purchase_handoff(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
  REPEAT('a', 64),
  (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT,
  'free',
  NULL
);
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
    'role',
    'authenticated'
  )::TEXT,
  TRUE
);
SELECT *
FROM public.cancel_signout_purchase_handoff(
  (SELECT handoff_id FROM signout_cancel_fixture),
  REPEAT('a', 64)
);

DO $$
DECLARE
  replay_was_idempotent BOOLEAN;
BEGIN
  SELECT receipt.already_cancelled
  INTO replay_was_idempotent
  FROM public.cancel_signout_purchase_handoff(
    (SELECT handoff_id FROM signout_cancel_fixture),
    REPEAT('a', 64)
  ) AS receipt;

  IF replay_was_idempotent IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION 'same-source cancellation was not idempotent';
  END IF;
END;
$$;
RESET ROLE;

SET LOCAL ROLE service_role;
INSERT INTO signout_transfer_fixture (handoff_id, expires_at)
SELECT *
FROM public.issue_signout_purchase_handoff(
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
  REPEAT('b', 64),
  (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT,
  'pro',
  NOW() + INTERVAL '1 year'
);
RESET ROLE;

-- The destination must have been created after the durable proof. This
-- prevents binding an unrelated pre-existing anonymous account even when its
-- bearer secret is known.
UPDATE auth.users
SET created_at = CASE
  WHEN id = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee5'
    THEN NOW() - INTERVAL '1 day'
  ELSE NOW()
END
WHERE id IN (
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2',
  'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee5'
);

-- A linked account cannot become the anonymous destination even with the full
-- bearer proof. The intended fresh anonymous session can bind exactly once.
SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    'dddddddd-dddd-4ddd-8ddd-ddddddddddd4',
    'role',
    'authenticated'
  )::TEXT,
  TRUE
);
DO $$
BEGIN
  BEGIN
    PERFORM public.bind_signout_purchase_handoff(
      (SELECT handoff_id FROM signout_transfer_fixture),
      REPEAT('b', 64)
    );
    RAISE EXCEPTION 'linked attacker unexpectedly bound the handoff';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    NULL;
  END;
END;
$$;

SELECT set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeee5',
    'role',
    'authenticated'
  )::TEXT,
  TRUE
);
DO $$
BEGIN
  BEGIN
    PERFORM public.bind_signout_purchase_handoff(
      (SELECT handoff_id FROM signout_transfer_fixture),
      REPEAT('b', 64)
    );
    RAISE EXCEPTION 'pre-existing anonymous account unexpectedly bound proof';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    NULL;
  END;
END;
$$;

SELECT set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2',
    'role',
    'authenticated'
  )::TEXT,
  TRUE
);
SELECT *
FROM public.bind_signout_purchase_handoff(
  (SELECT handoff_id FROM signout_transfer_fixture),
  REPEAT('b', 64)
);

-- Neither side of a bound handoff may enter destructive account deletion, and
-- operator cleanup must expose the destination as ineligible.
RESET ROLE;
SET LOCAL ROLE service_role;
DO $$
DECLARE
  blockers TEXT[];
  blocked_user UUID;
BEGIN
  FOREACH blocked_user IN ARRAY ARRAY[
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'::UUID,
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2'::UUID
  ] LOOP
    BEGIN
      PERFORM public.request_account_deletion(blocked_user);
      RAISE EXCEPTION 'bound handoff identity entered account deletion';
    EXCEPTION WHEN SQLSTATE '55000' THEN
      IF SQLERRM <> 'signout_handoff_destination_deletion_blocked' THEN
        RAISE;
      END IF;
    END;
  END LOOP;

  SELECT candidate.blockers
  INTO STRICT blockers
  FROM public.inspect_empty_ghost_cleanup_candidate(
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2',
    30
  ) AS candidate;
  IF NOT blockers @> ARRAY['signout_purchase_handoff_active']::TEXT[] THEN
    RAISE EXCEPTION 'bound destination was missing its cleanup blocker';
  END IF;
END;
$$;
RESET ROLE;

-- Defense in depth: a direct account-upgrade RPC cannot consume and later
-- delete the anonymous destination while purchase continuity is unresolved.
SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2',
    'role',
    'authenticated'
  )::TEXT,
  TRUE
);
DO $$
BEGIN
  BEGIN
    PERFORM public.issue_ghost_profile_merge_handoff(
      REPEAT('e', 64),
      'google',
      'signout-destination-provider-subject'
    );
    RAISE EXCEPTION 'bound destination prepared a profile merge';
  EXCEPTION WHEN SQLSTATE '55P03' THEN
    IF SQLERRM <> 'signout_purchase_handoff_pending' THEN
      RAISE;
    END IF;
  END;
END;
$$;
RESET ROLE;

-- If account deletion wins the Auth-row race before binding, bind must observe
-- the durable job and leave the proof unbound.
SET LOCAL ROLE service_role;
INSERT INTO signout_deletion_race_fixture
SELECT *
FROM public.issue_signout_purchase_handoff(
  'dddddddd-dddd-4ddd-8ddd-ddddddddddd4',
  REPEAT('f', 64),
  (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT,
  'free',
  NULL
);
SELECT *
FROM public.request_account_deletion(
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc3'
);
RESET ROLE;

UPDATE auth.users
SET created_at = NOW()
WHERE id = 'cccccccc-cccc-4ccc-8ccc-ccccccccccc3';

SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    'cccccccc-cccc-4ccc-8ccc-ccccccccccc3',
    'role',
    'authenticated'
  )::TEXT,
  TRUE
);
DO $$
BEGIN
  BEGIN
    PERFORM public.bind_signout_purchase_handoff(
      (SELECT handoff_id FROM signout_deletion_race_fixture),
      REPEAT('f', 64)
    );
    RAISE EXCEPTION 'deletion destination unexpectedly bound proof';
  EXCEPTION WHEN SQLSTATE '55P03' THEN
    IF SQLERRM <> 'signout_handoff_destination_deletion_in_progress' THEN
      RAISE;
    END IF;
  END;
END;
$$;
RESET ROLE;

UPDATE internal.signout_purchase_handoffs
SET status = 'superseded',
    updated_at = NOW()
WHERE id = (SELECT handoff_id FROM signout_deletion_race_fixture);

SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2',
    'role',
    'authenticated'
  )::TEXT,
  TRUE
);
DO $$
DECLARE
  replay_was_idempotent BOOLEAN;
BEGIN
  SELECT receipt.already_bound
  INTO replay_was_idempotent
  FROM public.bind_signout_purchase_handoff(
    (SELECT handoff_id FROM signout_transfer_fixture),
    REPEAT('b', 64)
  ) AS receipt;
  IF replay_was_idempotent IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION 'same-destination bind replay was not idempotent';
  END IF;
END;
$$;

SELECT set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    'cccccccc-cccc-4ccc-8ccc-ccccccccccc3',
    'role',
    'authenticated'
  )::TEXT,
  TRUE
);
DO $$
BEGIN
  BEGIN
    PERFORM public.bind_signout_purchase_handoff(
      (SELECT handoff_id FROM signout_transfer_fixture),
      REPEAT('b', 64)
    );
    RAISE EXCEPTION 'second anonymous destination replayed the handoff';
  EXCEPTION WHEN SQLSTATE 'P0002' THEN
    NULL;
  END;
END;
$$;

-- Once bound, even the original linked source cannot cancel the proof.
SELECT set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
    'role',
    'authenticated'
  )::TEXT,
  TRUE
);
DO $$
BEGIN
  BEGIN
    PERFORM public.cancel_signout_purchase_handoff(
      (SELECT handoff_id FROM signout_transfer_fixture),
      REPEAT('b', 64)
    );
    RAISE EXCEPTION 'source unexpectedly cancelled a bound handoff';
  EXCEPTION WHEN SQLSTATE '55000' THEN
    NULL;
  END;
END;
$$;

SELECT set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2',
    'role',
    'authenticated'
  )::TEXT,
  TRUE
);

-- The TTL limits only an unbound bearer capability. A bound proof must remain
-- completable after that timestamp because the StoreKit receipt may already
-- have moved and cancellation is intentionally forbidden.
RESET ROLE;
UPDATE internal.signout_purchase_handoffs
SET created_at = NOW() - INTERVAL '2 days',
    expires_at = NOW() - INTERVAL '1 day'
WHERE id = (SELECT handoff_id FROM signout_transfer_fixture);
SET LOCAL ROLE service_role;

SELECT *
FROM public.complete_signout_purchase_handoff(
  (SELECT handoff_id FROM signout_transfer_fixture),
  REPEAT('b', 64),
  'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2',
  (SELECT destination_snapshot_at_ms FROM signout_transfer_fixture),
  'pro',
  (
    SELECT expected_store_expires_at
    FROM internal.signout_purchase_handoffs
    WHERE id = (SELECT handoff_id FROM signout_transfer_fixture)
  )
);

DO $$
DECLARE
  replay_was_idempotent BOOLEAN;
BEGIN
  SELECT receipt.already_completed
  INTO replay_was_idempotent
  FROM public.complete_signout_purchase_handoff(
    (SELECT handoff_id FROM signout_transfer_fixture),
    REPEAT('b', 64),
    'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2',
    (SELECT destination_snapshot_at_ms FROM signout_transfer_fixture),
    'pro',
    (
      SELECT expected_store_expires_at
      FROM internal.signout_purchase_handoffs
      WHERE id = (SELECT handoff_id FROM signout_transfer_fixture)
    )
  ) AS receipt;
  IF replay_was_idempotent IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION 'same-destination completion was not idempotent';
  END IF;
END;
$$;

DO $$
BEGIN
  BEGIN
    PERFORM public.complete_signout_purchase_handoff(
      (SELECT handoff_id FROM signout_transfer_fixture),
      REPEAT('b', 64),
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2',
      (SELECT destination_snapshot_at_ms FROM signout_transfer_fixture),
      'free',
      NULL
    );
    RAISE EXCEPTION 'completed proof accepted a different StoreKit attestation';
  EXCEPTION WHEN SQLSTATE '22023' THEN
    NULL;
  END;
END;
$$;
RESET ROLE;

-- An abandoned prepared proof is no longer actionable after its bearer TTL and
-- must not leave aggregate operations alerting forever. Bound proofs remain
-- visible regardless of that TTL because receipt movement may have started.
INSERT INTO internal.signout_purchase_handoffs (
  source_user_id,
  secret_hash,
  source_snapshot_at_ms,
  expected_store_tier,
  status,
  created_at,
  updated_at,
  expires_at
)
VALUES (
  'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
  REPEAT('c', 64),
  (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT,
  'free',
  'prepared',
  NOW() - INTERVAL '2 days',
  NOW() - INTERVAL '2 days',
  NOW() - INTERVAL '1 day'
);

INSERT INTO internal.signout_purchase_handoffs (
  source_user_id,
  destination_user_id,
  secret_hash,
  source_snapshot_at_ms,
  expected_store_tier,
  status,
  created_at,
  updated_at,
  expires_at,
  bound_at
)
VALUES (
  'dddddddd-dddd-4ddd-8ddd-ddddddddddd4',
  'cccccccc-cccc-4ccc-8ccc-ccccccccccc3',
  REPEAT('d', 64),
  (EXTRACT(EPOCH FROM NOW()) * 1000)::BIGINT,
  'free',
  'bound',
  NOW() - INTERVAL '3 days',
  NOW() - INTERVAL '2 days',
  NOW() - INTERVAL '2 days',
  NOW() - INTERVAL '2 days'
);

SET LOCAL ROLE service_role;
DO $$
DECLARE
  health RECORD;
  expected_oldest TIMESTAMPTZ;
BEGIN
  SELECT handoff.created_at
  INTO STRICT expected_oldest
  FROM internal.signout_purchase_handoffs AS handoff
  WHERE handoff.secret_hash = REPEAT('d', 64);

  SELECT * INTO STRICT health
  FROM public.get_revenuecat_reconciliation_health();
  IF health.signout_prepared_count <> 0
     OR health.signout_bound_count <> 1
     OR health.oldest_signout_pending_at IS DISTINCT FROM expected_oldest
     OR health.oldest_signout_pending_age_seconds IS NULL
     OR health.oldest_signout_pending_age_seconds < 259200 THEN
    RAISE EXCEPTION
      'pending health did not exclude expired prepared and retain expired bound';
  END IF;
END;
$$;
RESET ROLE;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM internal.signout_purchase_handoffs AS handoff
    WHERE handoff.id = (SELECT handoff_id FROM signout_transfer_fixture)
      AND handoff.status = 'completed'
      AND handoff.source_user_id =
          'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
      AND handoff.destination_user_id =
          'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2'
  ) THEN
    RAISE EXCEPTION 'handoff did not retain its exact source and destination';
  END IF;

  IF (
    SELECT subscription_tier
    FROM public.users
    WHERE id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2'
  ) <> 'free'::public.subscription_tier_enum THEN
    RAISE EXCEPTION
      'database completion granted provider access before reconciliation';
  END IF;

  IF (
    SELECT public_username
    FROM public.users
    WHERE id = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1'
  ) <> 'signout_source_a1' OR (
    SELECT public_username
    FROM public.users
    WHERE id = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2'
  ) <> 'signout_destination_b2' THEN
    RAISE EXCEPTION 'sign-out handoff moved account profile data';
  END IF;

  IF (
    SELECT COUNT(*)
    FROM internal.revenuecat_reconciliation_queue AS queue
    WHERE queue.merian_user_id IN (
      'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1',
      'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbb2'
    )
      AND queue.lookup_app_user_id = UPPER(queue.merian_user_id::TEXT)
      AND queue.next_reconcile_at <= NOW()
      AND queue.attempt_count = 0
      AND queue.claim_token IS NULL
      AND queue.claimed_at IS NULL
      AND queue.claim_expires_at IS NULL
      AND queue.last_error_code IS NULL
  ) <> 2 THEN
    RAISE EXCEPTION
      'source and destination were not scheduled with canonical identities';
  END IF;
END;
$$;

SELECT extensions.pass(
  'sign-out purchase handoff is private, one-destination, idempotent, and data-preserving'
);
SELECT * FROM extensions.finish();
ROLLBACK;
