\set ON_ERROR_STOP on

BEGIN;
SELECT extensions.plan(1);

DO $$
BEGIN
  IF has_table_privilege(
    'authenticated',
    'internal.ghost_profile_merge_handoffs',
    'SELECT'
  ) OR has_table_privilege(
    'authenticated',
    'internal.ghost_user_cleanup_reservations',
    'SELECT'
  ) OR has_table_privilege(
    'authenticated',
    'internal.ghost_profile_merge_reference_policies',
    'SELECT'
  ) OR has_table_privilege(
    'service_role',
    'internal.ghost_profile_merge_reference_policies',
    'SELECT'
  ) THEN
    RAISE EXCEPTION
      'an API role unexpectedly has direct Ghost-merge internal-table access';
  END IF;

  IF has_function_privilege(
    'anon',
    'public.issue_ghost_profile_merge_handoff(text,text,text)',
    'EXECUTE'
  ) OR has_function_privilege(
    'anon',
    'public.consume_ghost_profile_merge_handoff(uuid,text)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'anon unexpectedly has ghost-merge RPC access';
  END IF;

  IF NOT has_function_privilege(
    'authenticated',
    'public.issue_ghost_profile_merge_handoff(text,text,text)',
    'EXECUTE'
  ) OR NOT has_function_privilege(
    'authenticated',
    'public.consume_ghost_profile_merge_handoff(uuid,text)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION
      'authenticated is missing a required ghost-merge RPC grant';
  END IF;

  IF has_function_privilege(
    'authenticated',
    'public.reparent_user_follows(uuid,uuid)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION
      'authenticated can still invoke the legacy arbitrary reparent helper';
  END IF;

  IF has_function_privilege(
    'authenticated',
    'public.record_ghost_profile_merge_auth_cleanup(uuid,boolean,text)',
    'EXECUTE'
  ) OR has_function_privilege(
    'authenticated',
    'public.claim_ghost_profile_merge_auth_cleanups(integer)',
    'EXECUTE'
  ) OR has_function_privilege(
    'authenticated',
    'public.finish_ghost_profile_merge_auth_cleanup(uuid,uuid,boolean,text)',
    'EXECUTE'
  ) OR has_function_privilege(
    'authenticated',
    'public.list_protected_ghost_profile_merge_sources()',
    'EXECUTE'
  ) OR has_function_privilege(
    'authenticated',
    'public.reserve_ghost_user_bulk_cleanup(uuid,integer)',
    'EXECUTE'
  ) OR has_function_privilege(
    'authenticated',
    'public.finish_ghost_user_bulk_cleanup(uuid,uuid,boolean,text)',
    'EXECUTE'
  ) OR has_function_privilege(
    'authenticated',
    'internal.perform_ghost_profile_merge(uuid,uuid)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION
      'authenticated unexpectedly has a privileged merge or cleanup grant';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM (
      VALUES ('anon'), ('authenticated'), ('service_role')
    ) AS api_role(role_name)
    WHERE has_function_privilege(
      api_role.role_name,
      'internal.refresh_public_author_identity(uuid)',
      'EXECUTE'
    )
  ) THEN
    RAISE EXCEPTION
      'an API role can execute the trusted identity-refresh implementation';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM (
      VALUES
        ('internal.assert_ghost_profile_merge_reference_policy_coverage()'),
        ('internal.assert_ghost_profile_merge_reference_preconditions(uuid)'),
        ('internal.merge_ghost_community_activity_actors(uuid,uuid)'),
        ('internal.merge_ghost_revenuecat_state(uuid,uuid)'),
        ('internal.assert_ghost_profile_merge_species_ledger(uuid[])'),
        ('internal.reparent_ghost_user_foreign_keys(uuid,uuid)')
    ) AS routine(routine_signature)
    CROSS JOIN (
      VALUES ('anon'), ('authenticated'), ('service_role')
    ) AS api_role(role_name)
    WHERE has_function_privilege(
      api_role.role_name,
      routine.routine_signature,
      'EXECUTE'
    )
  ) THEN
    RAISE EXCEPTION
      'an API role can execute a Ghost-merge policy implementation';
  END IF;

  IF NOT has_function_privilege(
    'service_role',
    'public.claim_ghost_profile_merge_auth_cleanups(integer)',
    'EXECUTE'
  ) OR NOT has_function_privilege(
    'service_role',
    'public.finish_ghost_profile_merge_auth_cleanup(uuid,uuid,boolean,text)',
    'EXECUTE'
  ) OR NOT has_function_privilege(
    'service_role',
    'public.list_protected_ghost_profile_merge_sources()',
    'EXECUTE'
  ) OR NOT has_function_privilege(
    'service_role',
    'public.reserve_ghost_user_bulk_cleanup(uuid,integer)',
    'EXECUTE'
  ) OR NOT has_function_privilege(
    'service_role',
    'public.finish_ghost_user_bulk_cleanup(uuid,uuid,boolean,text)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION
      'service_role is missing the durable Auth cleanup RPC grants';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM pg_constraint AS constraint_row
    WHERE constraint_row.contype = 'f'
      AND constraint_row.conrelid = 'public.ai_usage_events'::REGCLASS
      AND constraint_row.confrelid = 'auth.users'::REGCLASS
  ) THEN
    RAISE EXCEPTION
      'AI usage unexpectedly has an Auth FK that bypasses its delete guard';
  END IF;

  PERFORM internal.assert_ghost_profile_merge_reference_policy_coverage();
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
    '00000000-0000-0000-0000-000000000601'::UUID,
    'merge-ghost@naturebook.invalid',
    TRUE
  ),
  (
    '00000000-0000-0000-0000-000000000602'::UUID,
    'merge-target@naturebook.invalid',
    FALSE
  ),
  (
    '00000000-0000-0000-0000-000000000603'::UUID,
    'merge-attacker@naturebook.invalid',
    FALSE
  ),
  (
    '00000000-0000-0000-0000-000000000604'::UUID,
    'merge-cleanup-race@naturebook.invalid',
    TRUE
  )
) AS seed(user_id, email, is_anonymous);

INSERT INTO auth.identities (
  provider_id,
  user_id,
  identity_data,
  provider,
  last_sign_in_at,
  created_at,
  updated_at
)
VALUES
  (
    'merge-target-google-subject',
    '00000000-0000-0000-0000-000000000602',
    jsonb_build_object(
      'sub',
      'merge-target-google-subject',
      'email',
      'merge-target@naturebook.invalid'
    ),
    'google',
    NOW(),
    NOW(),
    NOW()
  ),
  (
    'merge-attacker-google-subject',
    '00000000-0000-0000-0000-000000000603',
    jsonb_build_object(
      'sub',
      'merge-attacker-google-subject',
      'email',
      'merge-attacker@naturebook.invalid'
    ),
    'google',
    NOW(),
    NOW(),
    NOW()
  );

INSERT INTO public.users (
  id,
  email,
  public_username,
  public_author_name,
  public_identity_source
)
VALUES
  (
    '00000000-0000-0000-0000-000000000601',
    'merge-ghost@naturebook.invalid',
    'merge_ghost_601',
    'Merge Ghost',
    'alias'
  ),
  (
    '00000000-0000-0000-0000-000000000602',
    'merge-target@naturebook.invalid',
    'merge_target_602',
    'Merge Target',
    'alias'
  ),
  (
    '00000000-0000-0000-0000-000000000603',
    'merge-attacker@naturebook.invalid',
    'merge_attacker_603',
    'Merge Attacker',
    'alias'
  ),
  (
    '00000000-0000-0000-0000-000000000604',
    'merge-cleanup-race@naturebook.invalid',
    'merge_cleanup_race_604',
    'Merge Cleanup Race',
    'alias'
  )
ON CONFLICT (id) DO UPDATE SET email = EXCLUDED.email;

-- Exercise the unconditional INSERT path independently of the later full
-- merge fixture: neither source nor destination has a queue row.
DELETE FROM internal.revenuecat_reconciliation_queue
WHERE merian_user_id IN (
  '00000000-0000-0000-0000-000000000601',
  '00000000-0000-0000-0000-000000000602'
);

SELECT internal.merge_ghost_revenuecat_state(
  '00000000-0000-0000-0000-000000000601',
  '00000000-0000-0000-0000-000000000602'
);

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM internal.revenuecat_reconciliation_queue
    WHERE merian_user_id = '00000000-0000-0000-0000-000000000601'
  ) OR NOT EXISTS (
    SELECT 1
    FROM internal.revenuecat_reconciliation_queue
    WHERE merian_user_id = '00000000-0000-0000-0000-000000000602'
      AND lookup_app_user_id =
          '00000000-0000-0000-0000-000000000602'
      AND next_reconcile_at <= pg_catalog.NOW()
      AND attempt_count = 0
      AND claim_token IS NULL
      AND claimed_at IS NULL
      AND claim_expires_at IS NULL
      AND last_error_code IS NULL
  ) THEN
    RAISE EXCEPTION
      'destination queue was not created from an entirely absent queue pair';
  END IF;
END;
$$;

-- Restore the empty baseline expected by the later transfer-state fixture.
DELETE FROM internal.revenuecat_reconciliation_queue
WHERE merian_user_id = '00000000-0000-0000-0000-000000000602';

UPDATE public.users
SET public_author_name = 'Guest Naturalist',
    public_identity_source = 'display_name',
    public_username = 'guest_merge_custom',
    custom_avatar_url = 'https://media.naturebook.invalid/guest-avatar.webp',
    custom_avatar_updated_at = NOW()
WHERE id = '00000000-0000-0000-0000-000000000601';

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
VALUES
  (
    '00000000-0000-0000-0000-000000000651',
    'Mergea prima',
    '{"en":"Merge first"}'::JSONB,
    'Animalia',
    'Chordata',
    'Aves',
    'Passeriformes',
    'Mergeidae',
    'Mergea',
    'Test region'
  ),
  (
    '00000000-0000-0000-0000-000000000652',
    'Mergea secunda',
    '{"en":"Merge second"}'::JSONB,
    'Animalia',
    'Chordata',
    'Aves',
    'Passeriformes',
    'Mergeidae',
    'Mergea',
    'Test region'
  );

INSERT INTO public.scans (id, user_id, species_id, ai_confidence_score)
VALUES
  (
    '00000000-0000-0000-0000-000000000611',
    '00000000-0000-0000-0000-000000000601',
    NULL,
    0.92
  ),
  (
    '00000000-0000-0000-0000-000000000612',
    '00000000-0000-0000-0000-000000000601',
    '00000000-0000-0000-0000-000000000651',
    0.91
  ),
  (
    '00000000-0000-0000-0000-000000000613',
    '00000000-0000-0000-0000-000000000601',
    '00000000-0000-0000-0000-000000000651',
    0.90
  ),
  (
    '00000000-0000-0000-0000-000000000614',
    '00000000-0000-0000-0000-000000000601',
    '00000000-0000-0000-0000-000000000652',
    0.89
  ),
  (
    '00000000-0000-0000-0000-000000000615',
    '00000000-0000-0000-0000-000000000602',
    '00000000-0000-0000-0000-000000000651',
    0.88
  ),
  (
    '00000000-0000-0000-0000-000000000616',
    '00000000-0000-0000-0000-000000000602',
    NULL,
    0.87
  );

-- The collision group exercises the handler's UPDATE/DELETE path. The
-- source-only group must remain untouched by the handler so the reviewed
-- generic reparent pass can move it without taking a group lock after an
-- actor lock.
INSERT INTO public.explore_posts (id, user_id, scan_id)
VALUES (
  '00000000-0000-0000-0000-000000000631',
  '00000000-0000-0000-0000-000000000601',
  '00000000-0000-0000-0000-000000000611'
);

INSERT INTO public.explore_community_requests (
  id,
  post_id,
  scan_id,
  requested_by
)
VALUES (
  '00000000-0000-0000-0000-000000000632',
  '00000000-0000-0000-0000-000000000631',
  '00000000-0000-0000-0000-000000000611',
  '00000000-0000-0000-0000-000000000601'
);

INSERT INTO internal.community_identification_activity_groups (
  id,
  request_id,
  post_id,
  request_generation_at,
  activity_type,
  burst_started_at,
  activity_at
)
VALUES
  (
    '00000000-0000-0000-0000-000000000641',
    '00000000-0000-0000-0000-000000000632',
    '00000000-0000-0000-0000-000000000631',
    NOW() - INTERVAL '2 hours',
    'suggestion_burst',
    NOW() - INTERVAL '90 minutes',
    NOW() - INTERVAL '60 minutes'
  ),
  (
    '00000000-0000-0000-0000-000000000642',
    '00000000-0000-0000-0000-000000000632',
    '00000000-0000-0000-0000-000000000631',
    NOW() - INTERVAL '2 hours',
    'suggestion_burst',
    NOW() - INTERVAL '45 minutes',
    NOW() - INTERVAL '30 minutes'
  );

INSERT INTO internal.community_identification_activity_actors (
  activity_group_id,
  user_id,
  suggestion_count,
  last_suggested_at
)
VALUES
  (
    '00000000-0000-0000-0000-000000000641',
    '00000000-0000-0000-0000-000000000601',
    2,
    NOW() - INTERVAL '70 minutes'
  ),
  (
    '00000000-0000-0000-0000-000000000641',
    '00000000-0000-0000-0000-000000000602',
    3,
    NOW() - INTERVAL '65 minutes'
  ),
  (
    '00000000-0000-0000-0000-000000000642',
    '00000000-0000-0000-0000-000000000601',
    4,
    NOW() - INTERVAL '35 minutes'
  );

INSERT INTO public.collections (id, user_id, name)
VALUES (
  '00000000-0000-0000-0000-000000000621',
  '00000000-0000-0000-0000-000000000601',
  'Guest collection'
);

INSERT INTO public.user_species_preferences (
  user_id,
  scientific_name,
  preferred_common_name
)
VALUES
  (
    '00000000-0000-0000-0000-000000000601',
    'Danaus plexippus',
    'Guest monarch name'
  ),
  (
    '00000000-0000-0000-0000-000000000602',
    'Danaus plexippus',
    'Target monarch name'
  );

INSERT INTO public.user_follows (follower_user_id, followee_user_id)
VALUES
  (
    '00000000-0000-0000-0000-000000000601',
    '00000000-0000-0000-0000-000000000603'
  ),
  (
    '00000000-0000-0000-0000-000000000602',
    '00000000-0000-0000-0000-000000000603'
  ),
  (
    '00000000-0000-0000-0000-000000000603',
    '00000000-0000-0000-0000-000000000601'
  ),
  (
    '00000000-0000-0000-0000-000000000603',
    '00000000-0000-0000-0000-000000000602'
  ),
  (
    '00000000-0000-0000-0000-000000000601',
    '00000000-0000-0000-0000-000000000602'
  );

INSERT INTO public.scan_ingestion_jobs (scan_id, user_id)
VALUES
  (
    '00000000-0000-0000-0000-000000000611',
    '00000000-0000-0000-0000-000000000601'
  ),
  (
    '00000000-0000-0000-0000-000000000611',
    '00000000-0000-0000-0000-000000000602'
  );

INSERT INTO public.scan_ingestion_intents (scan_id, user_id)
VALUES
  (
    '00000000-0000-0000-0000-000000000611',
    '00000000-0000-0000-0000-000000000601'
  ),
  (
    '00000000-0000-0000-0000-000000000611',
    '00000000-0000-0000-0000-000000000602'
  );

INSERT INTO public.scan_deferred_context_updates (user_id, scan_id)
VALUES
  (
    '00000000-0000-0000-0000-000000000601',
    '00000000-0000-0000-0000-000000000611'
  ),
  (
    '00000000-0000-0000-0000-000000000602',
    '00000000-0000-0000-0000-000000000611'
  );

INSERT INTO public.failed_scan_ingestions (scan_id, user_id, error_message)
VALUES (
  '00000000-0000-0000-0000-000000000611',
  '00000000-0000-0000-0000-000000000601',
  'merge test'
);

INSERT INTO public.ai_usage_events (user_id, operation, model)
VALUES (
  '00000000-0000-0000-0000-000000000601',
  'merge-test',
  'test-model'
);

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
VALUES
  (
    'merge-transfer-event',
    200,
    'TRANSFER',
    REPEAT('1', 64),
    1,
    'applied',
    2,
    2,
    0
  ),
  (
    'merge-source-watermark',
    300,
    'TEST',
    REPEAT('2', 64),
    1,
    'ignored',
    0,
    0,
    0
  ),
  (
    'merge-target-watermark',
    100,
    'TEST',
    REPEAT('3', 64),
    1,
    'ignored',
    0,
    0,
    0
  );

INSERT INTO internal.revenuecat_webhook_event_subjects (
  event_id,
  merian_user_id,
  subject_kind,
  authoritative_snapshot_at_ms,
  target_tier,
  target_expires_at,
  outcome,
  entitlement_version
)
VALUES
  (
    'merge-transfer-event',
    '00000000-0000-0000-0000-000000000601',
    'transfer_source',
    200,
    'free',
    NULL,
    'applied',
    1
  ),
  (
    'merge-transfer-event',
    '00000000-0000-0000-0000-000000000602',
    'transfer_destination',
    200,
    'free',
    NULL,
    'applied',
    1
  );

INSERT INTO internal.revenuecat_customer_state (
  merian_user_id,
  last_event_id,
  last_event_timestamp_ms,
  last_authoritative_snapshot_at_ms
)
VALUES
  (
    '00000000-0000-0000-0000-000000000601',
    'merge-source-watermark',
    300,
    300
  ),
  (
    '00000000-0000-0000-0000-000000000602',
    'merge-target-watermark',
    100,
    100
  );

-- Deliberately leave the source queue absent. Completion must still repair a
-- pre-existing delayed and leased destination queue.
DELETE FROM internal.revenuecat_reconciliation_queue
WHERE merian_user_id = '00000000-0000-0000-0000-000000000601';

INSERT INTO internal.revenuecat_reconciliation_queue (
  merian_user_id,
  lookup_app_user_id,
  next_reconcile_at,
  attempt_count,
  claim_token,
  claimed_at,
  claim_expires_at,
  last_error_code
)
VALUES (
  '00000000-0000-0000-0000-000000000602',
  '00000000-0000-0000-0000-000000000602',
  NOW() + INTERVAL '10 days',
  2,
  '00000000-0000-0000-0000-000000000672',
  NOW(),
  NOW() + INTERVAL '10 minutes',
  'target_failure'
)
ON CONFLICT (merian_user_id) DO UPDATE
SET lookup_app_user_id = EXCLUDED.lookup_app_user_id,
    next_reconcile_at = EXCLUDED.next_reconcile_at,
    attempt_count = EXCLUDED.attempt_count,
    claim_token = EXCLUDED.claim_token,
    claimed_at = EXCLUDED.claimed_at,
    claim_expires_at = EXCLUDED.claim_expires_at,
    last_error_code = EXCLUDED.last_error_code;

CREATE TEMP TABLE merge_test_handoff (handoff_id UUID NOT NULL);
GRANT SELECT, INSERT ON merge_test_handoff TO authenticated;
GRANT SELECT ON merge_test_handoff TO service_role;

SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    '00000000-0000-0000-0000-000000000601',
    'role',
    'authenticated'
  )::TEXT,
  TRUE
);

INSERT INTO merge_test_handoff (handoff_id)
SELECT handoff_id
FROM public.issue_ghost_profile_merge_handoff(
  REPEAT('a', 64),
  'google',
  'merge-target-google-subject'
);

RESET ROLE;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM internal.ghost_profile_merge_handoffs AS handoff
    WHERE handoff.id = (SELECT handoff_id FROM merge_test_handoff)
      AND handoff.expires_at BETWEEN
          handoff.created_at + INTERVAL '29 days'
          AND handoff.created_at + INTERVAL '31 days'
  ) THEN
    RAISE EXCEPTION 'handoff does not have the documented 30-day recovery TTL';
  END IF;
END;
$$;

CREATE TEMP TABLE merge_test_bulk_cleanup_reservation (
  reservation_token UUID NOT NULL
);
GRANT SELECT, INSERT ON merge_test_bulk_cleanup_reservation TO service_role;

SET LOCAL ROLE service_role;
INSERT INTO merge_test_bulk_cleanup_reservation (reservation_token)
SELECT public.reserve_ghost_user_bulk_cleanup(
  '00000000-0000-0000-0000-000000000604',
  15
);
RESET ROLE;

-- A future user FK without a reviewed policy must stop the orchestrator before
-- its first mutating helper. This fixture represents an independently shipped
-- schema migration that forgot to classify its ownership semantics.
CREATE TABLE internal.ghost_merge_unclassified_fixture (
  user_id UUID PRIMARY KEY REFERENCES public.users(id)
);
INSERT INTO internal.ghost_merge_unclassified_fixture (user_id)
VALUES ('00000000-0000-0000-0000-000000000604');

DO $$
DECLARE
  failure_message TEXT;
BEGIN
  BEGIN
    PERFORM internal.perform_ghost_profile_merge(
      '00000000-0000-0000-0000-000000000604',
      '00000000-0000-0000-0000-000000000603'
    );
    RAISE EXCEPTION 'unclassified user FK did not stop the merge';
  EXCEPTION WHEN SQLSTATE '55000' THEN
    GET STACKED DIAGNOSTICS failure_message = MESSAGE_TEXT;
    IF failure_message NOT LIKE
       'ghost_merge_unclassified_reference:%ghost_merge_unclassified_fixture%'
    THEN
      RAISE EXCEPTION
        'unclassified user FK raised an unexpected failure: %',
        failure_message;
    END IF;
  END;

  IF NOT EXISTS (
    SELECT 1
    FROM public.users
    WHERE id = '00000000-0000-0000-0000-000000000604'
  ) OR NOT EXISTS (
    SELECT 1
    FROM public.users
    WHERE id = '00000000-0000-0000-0000-000000000603'
  ) THEN
    RAISE EXCEPTION 'topology failure mutated a source or target profile';
  END IF;
END;
$$;

DROP TABLE internal.ghost_merge_unclassified_fixture;

SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    '00000000-0000-0000-0000-000000000604',
    'role',
    'authenticated'
  )::TEXT,
  TRUE
);
DO $$
BEGIN
  BEGIN
    PERFORM public.issue_ghost_profile_merge_handoff(
      REPEAT('d', 64),
      'google',
      'cleanup-race-subject'
    );
    RAISE EXCEPTION
      'bulk cleanup reservation did not block handoff issuance';
  EXCEPTION WHEN SQLSTATE '55P03' THEN
    NULL;
  END;
END;
$$;
RESET ROLE;

SET LOCAL ROLE service_role;
SELECT public.finish_ghost_user_bulk_cleanup(
  '00000000-0000-0000-0000-000000000604',
  (SELECT reservation_token FROM merge_test_bulk_cleanup_reservation),
  FALSE,
  'test_release'
);
RESET ROLE;

-- A corrupted private species ledger must make the scan reparent fail with
-- the guarded diagnostic, and the whole merge subtransaction must roll back.
INSERT INTO public.scans (id, user_id, species_id, ai_confidence_score)
VALUES (
  '00000000-0000-0000-0000-000000000617',
  '00000000-0000-0000-0000-000000000604',
  '00000000-0000-0000-0000-000000000651',
  0.86
);

DELETE FROM internal.user_species_scan_counts
WHERE user_id = '00000000-0000-0000-0000-000000000604'
  AND species_id = '00000000-0000-0000-0000-000000000651';

DO $$
DECLARE
  failure_message TEXT;
BEGIN
  BEGIN
    PERFORM internal.perform_ghost_profile_merge(
      '00000000-0000-0000-0000-000000000604',
      '00000000-0000-0000-0000-000000000603'
    );
    RAISE EXCEPTION 'species ledger underflow did not stop the merge';
  EXCEPTION WHEN SQLSTATE '23514' THEN
    GET STACKED DIAGNOSTICS failure_message = MESSAGE_TEXT;
    IF failure_message <> 'user_species_scan_count_underflow' THEN
      RAISE EXCEPTION
        'species ledger underflow raised an unexpected failure: %',
        failure_message;
    END IF;
  END;

  IF NOT EXISTS (
    SELECT 1
    FROM public.users
    WHERE id = '00000000-0000-0000-0000-000000000604'
  ) OR NOT EXISTS (
    SELECT 1
    FROM public.users
    WHERE id = '00000000-0000-0000-0000-000000000603'
  ) OR NOT EXISTS (
    SELECT 1
    FROM public.scans
    WHERE id = '00000000-0000-0000-0000-000000000617'
      AND user_id = '00000000-0000-0000-0000-000000000604'
  ) THEN
    RAISE EXCEPTION 'species ledger failure did not roll back the merge';
  END IF;
END;
$$;

INSERT INTO internal.user_species_scan_counts (
  user_id,
  species_id,
  scan_count
)
VALUES (
  '00000000-0000-0000-0000-000000000604',
  '00000000-0000-0000-0000-000000000651',
  1
);

-- An authenticated permanent account with the wrong provider subject cannot
-- consume a valid source-issued handoff even when it knows the full verifier.
SET LOCAL ROLE authenticated;
SELECT set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    '00000000-0000-0000-0000-000000000603',
    'role',
    'authenticated'
  )::TEXT,
  TRUE
);
DO $$
BEGIN
  BEGIN
    PERFORM public.issue_ghost_profile_merge_handoff(
      REPEAT('b', 64),
      'google',
      'merge-attacker-google-subject'
    );
    RAISE EXCEPTION
      'permanent account unexpectedly issued a source handoff';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    NULL;
  END;

  BEGIN
    PERFORM public.consume_ghost_profile_merge_handoff(
      (SELECT handoff_id FROM merge_test_handoff),
      REPEAT('a', 64)
    );
    RAISE EXCEPTION
      'provider-mismatched attacker unexpectedly consumed the handoff';
  EXCEPTION WHEN SQLSTATE '42501' THEN
    NULL;
  END;
END;
$$;

-- The bound provider identity can consume exactly once, and a retry by that
-- same destination is an idempotent receipt lookup.
SELECT set_config(
  'request.jwt.claims',
  jsonb_build_object(
    'sub',
    '00000000-0000-0000-0000-000000000602',
    'role',
    'authenticated'
  )::TEXT,
  TRUE
);
SELECT *
FROM public.consume_ghost_profile_merge_handoff(
  (SELECT handoff_id FROM merge_test_handoff),
  REPEAT('a', 64)
);

DO $$
DECLARE
  replay_was_idempotent BOOLEAN;
BEGIN
  SELECT receipt.already_merged
  INTO replay_was_idempotent
  FROM public.consume_ghost_profile_merge_handoff(
    (SELECT handoff_id FROM merge_test_handoff),
    REPEAT('a', 64)
  ) AS receipt;

  IF replay_was_idempotent IS DISTINCT FROM TRUE THEN
    RAISE EXCEPTION 'same-destination replay was not idempotent';
  END IF;
END;
$$;

RESET ROLE;

-- The merge displaced this old destination lease. A stale worker must not be
-- able to apply provider state after completion reset the queue claim.
SET LOCAL ROLE service_role;
DO $$
DECLARE
  failure_message TEXT;
BEGIN
  BEGIN
    PERFORM public.apply_revenuecat_reconciliation(
      '00000000-0000-0000-0000-000000000602',
      '00000000-0000-0000-0000-000000000672',
      999,
      'pro',
      NULL
    );
    RAISE EXCEPTION 'displaced RevenueCat claim unexpectedly applied state';
  EXCEPTION WHEN SQLSTATE '55000' THEN
    GET STACKED DIAGNOSTICS failure_message = MESSAGE_TEXT;
    IF failure_message <> 'revenuecat_reconciliation_claim_lost' THEN
      RAISE EXCEPTION
        'displaced RevenueCat claim raised an unexpected failure: %',
        failure_message;
    END IF;
  END;
END;
$$;
RESET ROLE;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.users
    WHERE id = '00000000-0000-0000-0000-000000000602'
      AND subscription_tier = 'pro'::public.subscription_tier_enum
  ) OR NOT EXISTS (
    SELECT 1
    FROM internal.revenuecat_customer_state
    WHERE merian_user_id = '00000000-0000-0000-0000-000000000602'
      AND last_authoritative_snapshot_at_ms = 300
  ) THEN
    RAISE EXCEPTION 'displaced RevenueCat claim mutated provider state';
  END IF;
END;
$$;

CREATE TEMP TABLE merge_test_cleanup_claim (
  handoff_id UUID NOT NULL,
  claim_token UUID NOT NULL
);
GRANT SELECT, INSERT ON merge_test_cleanup_claim TO service_role;

SET LOCAL ROLE service_role;
INSERT INTO merge_test_cleanup_claim (handoff_id, claim_token)
SELECT handoff_id, claim_token
FROM public.claim_ghost_profile_merge_auth_cleanups(25)
WHERE handoff_id = (SELECT handoff_id FROM merge_test_handoff);

DO $$
BEGIN
  IF (
    SELECT COUNT(*)
    FROM merge_test_cleanup_claim
  ) <> 1 THEN
    RAISE EXCEPTION 'merged Auth cleanup receipt was not claimed exactly once';
  END IF;

  PERFORM public.finish_ghost_profile_merge_auth_cleanup(
    (SELECT handoff_id FROM merge_test_cleanup_claim),
    (SELECT claim_token FROM merge_test_cleanup_claim),
    TRUE,
    NULL
  );
END;
$$;
RESET ROLE;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.users
    WHERE id = '00000000-0000-0000-0000-000000000601'
  ) THEN
    RAISE EXCEPTION 'source public profile survived the committed merge';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM auth.users
    WHERE id = '00000000-0000-0000-0000-000000000601'
  ) THEN
    RAISE EXCEPTION
      'database transaction deleted Auth before Edge cleanup confirmation';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM internal.ghost_profile_merge_handoffs AS handoff
    WHERE handoff.id = (SELECT handoff_id FROM merge_test_handoff)
      AND handoff.auth_deleted_at IS NOT NULL
      AND handoff.cleanup_attempt_count = 1
      AND handoff.cleanup_claim_token IS NULL
      AND handoff.cleanup_claimed_at IS NULL
  ) THEN
    RAISE EXCEPTION
      'durable cleanup worker did not finalize its claimed receipt';
  END IF;

  IF (
    SELECT COUNT(*)
    FROM public.scans
    WHERE id IN (
      '00000000-0000-0000-0000-000000000611',
      '00000000-0000-0000-0000-000000000612',
      '00000000-0000-0000-0000-000000000613',
      '00000000-0000-0000-0000-000000000614',
      '00000000-0000-0000-0000-000000000615',
      '00000000-0000-0000-0000-000000000616'
    )
      AND user_id = '00000000-0000-0000-0000-000000000602'
  ) <> 6 THEN
    RAISE EXCEPTION 'source scans were not reparented';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM internal.user_species_scan_counts
    WHERE user_id = '00000000-0000-0000-0000-000000000601'
  ) OR NOT EXISTS (
    SELECT 1
    FROM internal.user_species_scan_counts
    WHERE user_id = '00000000-0000-0000-0000-000000000602'
      AND species_id = '00000000-0000-0000-0000-000000000651'
      AND scan_count = 3
  ) OR NOT EXISTS (
    SELECT 1
    FROM internal.user_species_scan_counts
    WHERE user_id = '00000000-0000-0000-0000-000000000602'
      AND species_id = '00000000-0000-0000-0000-000000000652'
      AND scan_count = 1
  ) OR (
    SELECT total_species_discovered
    FROM public.users
    WHERE id = '00000000-0000-0000-0000-000000000602'
  ) <> 2 THEN
    RAISE EXCEPTION
      'species ledger or public distinct-species projection drifted during merge';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.collections
    WHERE id = '00000000-0000-0000-0000-000000000621'
      AND user_id = '00000000-0000-0000-0000-000000000602'
  ) THEN
    RAISE EXCEPTION 'source collection was not reparented';
  END IF;

  IF (
    SELECT COUNT(*)
    FROM public.user_species_preferences
    WHERE user_id = '00000000-0000-0000-0000-000000000602'
      AND scientific_name = 'Danaus plexippus'
      AND preferred_common_name = 'Target monarch name'
  ) <> 1 THEN
    RAISE EXCEPTION 'target preference did not win the unique conflict';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.user_follows
    WHERE follower_user_id = '00000000-0000-0000-0000-000000000601'
       OR followee_user_id = '00000000-0000-0000-0000-000000000601'
       OR follower_user_id = followee_user_id
  ) THEN
    RAISE EXCEPTION 'source or self follow survived relationship merge';
  END IF;

  IF (
    SELECT COUNT(*)
    FROM public.user_follows
    WHERE (
      follower_user_id = '00000000-0000-0000-0000-000000000602'
      AND followee_user_id = '00000000-0000-0000-0000-000000000603'
    ) OR (
      follower_user_id = '00000000-0000-0000-0000-000000000603'
      AND followee_user_id = '00000000-0000-0000-0000-000000000602'
    )
  ) <> 2 THEN
    RAISE EXCEPTION 'follow edges were not deduplicated in both directions';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.explore_post_notifications
    WHERE user_id = '00000000-0000-0000-0000-000000000601'
       OR triggering_user_id =
          '00000000-0000-0000-0000-000000000601'
       OR '00000000-0000-0000-0000-000000000601'::UUID =
          ANY(recent_actor_ids)
  ) THEN
    RAISE EXCEPTION 'derived source notification survived the merge';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM internal.community_identification_activity_actors
    WHERE user_id = '00000000-0000-0000-0000-000000000601'
  ) OR (
    SELECT COUNT(*)
    FROM internal.community_identification_activity_actors
    WHERE user_id = '00000000-0000-0000-0000-000000000602'
      AND activity_group_id IN (
        '00000000-0000-0000-0000-000000000641',
        '00000000-0000-0000-0000-000000000642'
      )
  ) <> 2 OR NOT EXISTS (
    SELECT 1
    FROM internal.community_identification_activity_actors
    WHERE activity_group_id =
          '00000000-0000-0000-0000-000000000641'
      AND user_id = '00000000-0000-0000-0000-000000000602'
      AND suggestion_count = 5
  ) OR NOT EXISTS (
    SELECT 1
    FROM internal.community_identification_activity_actors
    WHERE activity_group_id =
          '00000000-0000-0000-0000-000000000642'
      AND user_id = '00000000-0000-0000-0000-000000000602'
      AND suggestion_count = 4
  ) THEN
    RAISE EXCEPTION
      'Community activity actors were not coalesced and reparented exactly';
  END IF;

  IF (
    SELECT COUNT(*)
    FROM public.scan_ingestion_jobs
    WHERE user_id = '00000000-0000-0000-0000-000000000602'
      AND scan_id = '00000000-0000-0000-0000-000000000611'
  ) <> 1 OR (
    SELECT COUNT(*)
    FROM public.scan_ingestion_intents
    WHERE user_id = '00000000-0000-0000-0000-000000000602'
      AND scan_id = '00000000-0000-0000-0000-000000000611'
  ) <> 1 OR (
    SELECT COUNT(*)
    FROM public.scan_deferred_context_updates
    WHERE user_id = '00000000-0000-0000-0000-000000000602'
      AND scan_id = '00000000-0000-0000-0000-000000000611'
  ) <> 1 THEN
    RAISE EXCEPTION 'operational ledger conflicts were not deduplicated';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.failed_scan_ingestions
    WHERE user_id = '00000000-0000-0000-0000-000000000601'
  ) OR EXISTS (
    SELECT 1
    FROM public.ai_usage_events
    WHERE user_id = '00000000-0000-0000-0000-000000000601'
  ) THEN
    RAISE EXCEPTION 'non-profile source references survived the merge';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.ai_usage_events
    WHERE user_id = '00000000-0000-0000-0000-000000000602'
      AND operation = 'merge-test'
      AND model = 'test-model'
  ) THEN
    RAISE EXCEPTION
      'append-only AI usage attribution was not reparented intact';
  END IF;

  IF EXISTS (
    SELECT 1
    FROM internal.revenuecat_webhook_event_subjects
    WHERE merian_user_id = '00000000-0000-0000-0000-000000000601'
  ) OR EXISTS (
    SELECT 1
    FROM internal.revenuecat_customer_state
    WHERE merian_user_id = '00000000-0000-0000-0000-000000000601'
  ) OR EXISTS (
    SELECT 1
    FROM internal.revenuecat_reconciliation_queue
    WHERE merian_user_id = '00000000-0000-0000-0000-000000000601'
  ) THEN
    RAISE EXCEPTION 'source RevenueCat state survived the merge';
  END IF;

  IF (
    SELECT COUNT(*)
    FROM internal.revenuecat_webhook_event_subjects
    WHERE event_id = 'merge-transfer-event'
      AND merian_user_id = '00000000-0000-0000-0000-000000000602'
  ) <> 1 OR NOT EXISTS (
    SELECT 1
    FROM internal.revenuecat_customer_state
    WHERE merian_user_id = '00000000-0000-0000-0000-000000000602'
      AND last_event_id = 'merge-source-watermark'
      AND last_event_timestamp_ms = 300
      AND last_authoritative_snapshot_at_ms = 300
  ) OR NOT EXISTS (
    SELECT 1
    FROM internal.revenuecat_reconciliation_queue
    WHERE merian_user_id = '00000000-0000-0000-0000-000000000602'
      AND lookup_app_user_id =
          '00000000-0000-0000-0000-000000000602'
      AND next_reconcile_at <= NOW()
      AND attempt_count = 0
      AND claim_token IS NULL
      AND claimed_at IS NULL
      AND claim_expires_at IS NULL
      AND last_error_code IS NULL
  ) THEN
    RAISE EXCEPTION 'RevenueCat conflict state was not normalized';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM public.users
    WHERE id = '00000000-0000-0000-0000-000000000602'
      AND public_author_name = 'Guest Naturalist'
      AND public_identity_source = 'display_name'
      AND public_username = 'guest_merge_custom'
      AND custom_avatar_url =
          'https://media.naturebook.invalid/guest-avatar.webp'
  ) THEN
    RAISE EXCEPTION 'guest-customized public identity was not preserved';
  END IF;
END;
$$;

-- Exercise both trusted callers after the merge assertions: Auth metadata
-- updates use the private implementation, while backend callers retain the
-- guarded public service-role wrapper.
UPDATE auth.users
SET raw_user_meta_data =
      raw_user_meta_data || '{"catalog_identity_refresh_probe":true}'::JSONB
WHERE id = '00000000-0000-0000-0000-000000000602';

SET LOCAL ROLE service_role;
SELECT public.refresh_public_author_identity(
  '00000000-0000-0000-0000-000000000602'
);
RESET ROLE;

SELECT extensions.pass(
  'provider-bound handoff rejects takeover and atomically preserves source data'
);
SELECT * FROM extensions.finish();
ROLLBACK;
