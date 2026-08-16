\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(1);

DO $rollout_control$
DECLARE
  receipt RECORD;
  current_config internal.purchase_identity_rollout_config%ROWTYPE;
BEGIN
  IF has_table_privilege(
    'service_role',
    'internal.purchase_identity_rollout_operations',
    'SELECT'
  ) OR has_function_privilege(
    'service_role',
    'internal.apply_purchase_identity_rollout_operation(uuid,integer,text,text,text,text,text,text,text,text,text,text,integer,integer,uuid)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'rollout control is exposed outside the database owner';
  END IF;

  BEGIN
    PERFORM internal.apply_purchase_identity_rollout_operation(
      '31000000-0000-4000-8000-000000000000',
      1,
      'production',
      'wrongprojectref000000',
      (SELECT system_identifier::TEXT FROM pg_catalog.PG_CONTROL_SYSTEM()),
      'enable_stable',
      REPEAT('1', 40),
      REPEAT('2', 64),
      REPEAT('3', 64),
      REPEAT('4', 64),
      'legacy',
      'dual_read',
      1,
      3,
      NULL
    );
    RAISE EXCEPTION 'wrong Supabase project target was accepted';
  EXCEPTION
    WHEN SQLSTATE '22023' THEN
      IF SQLERRM <> 'purchase_identity_rollout_invalid_request' THEN
        RAISE;
      END IF;
  END;

  BEGIN
    PERFORM internal.apply_purchase_identity_rollout_operation(
      '31000000-0000-4000-8000-000000000000',
      1,
      'production',
      'qlarqavoqhkuwzmevrmf',
      '0',
      'enable_stable',
      REPEAT('1', 40),
      REPEAT('2', 64),
      REPEAT('3', 64),
      REPEAT('4', 64),
      'legacy',
      'dual_read',
      1,
      3,
      NULL
    );
    RAISE EXCEPTION 'wrong database system target was accepted';
  EXCEPTION
    WHEN SQLSTATE '55000' THEN
      IF SQLERRM <> 'purchase_identity_rollout_database_target_mismatch' THEN
        RAISE;
      END IF;
  END;

  SELECT * INTO receipt
  FROM internal.apply_purchase_identity_rollout_operation(
    '31000000-0000-4000-8000-000000000001',
    1,
    'production',
    'qlarqavoqhkuwzmevrmf',
    (SELECT system_identifier::TEXT FROM pg_catalog.PG_CONTROL_SYSTEM()),
    'enable_stable',
    REPEAT('1', 40),
    REPEAT('2', 64),
    REPEAT('3', 64),
    REPEAT('4', 64),
    'legacy',
    'dual_read',
    1,
    3,
    NULL
  );
  IF receipt.already_applied
     OR receipt.principal_mode <> 'stable'
     OR receipt.account_grant_mode <> 'dual_read'
     OR receipt.minimum_client_protocol <> 3 THEN
    RAISE EXCEPTION 'stable rollout receipt is invalid';
  END IF;

  SELECT * INTO receipt
  FROM internal.apply_purchase_identity_rollout_operation(
    '31000000-0000-4000-8000-000000000001',
    1,
    'production',
    'qlarqavoqhkuwzmevrmf',
    (SELECT system_identifier::TEXT FROM pg_catalog.PG_CONTROL_SYSTEM()),
    'enable_stable',
    REPEAT('1', 40),
    REPEAT('2', 64),
    REPEAT('3', 64),
    REPEAT('4', 64),
    'legacy',
    'dual_read',
    1,
    3,
    NULL
  );
  IF NOT receipt.already_applied THEN
    RAISE EXCEPTION 'exact rollout replay was not idempotent';
  END IF;

  BEGIN
    PERFORM internal.apply_purchase_identity_rollout_operation(
      '31000000-0000-4000-8000-000000000001',
      1,
      'production',
      'qlarqavoqhkuwzmevrmf',
      (SELECT system_identifier::TEXT FROM pg_catalog.PG_CONTROL_SYSTEM()),
      'enable_stable',
      REPEAT('1', 40),
      REPEAT('2', 64),
      REPEAT('3', 64),
      REPEAT('5', 64),
      'legacy',
      'dual_read',
      1,
      3,
      NULL
    );
    RAISE EXCEPTION 'mismatched rollout replay was accepted';
  EXCEPTION
    WHEN SQLSTATE '22023' THEN
      IF SQLERRM <> 'purchase_identity_rollout_replay_mismatch' THEN
        RAISE;
      END IF;
  END;

  PERFORM internal.apply_purchase_identity_rollout_operation(
    '31000000-0000-4000-8000-000000000002',
    1,
    'production',
    'qlarqavoqhkuwzmevrmf',
    (SELECT system_identifier::TEXT FROM pg_catalog.PG_CONTROL_SYSTEM()),
    'enable_authoritative',
    REPEAT('6', 40),
    REPEAT('7', 64),
    REPEAT('8', 64),
    REPEAT('9', 64),
    'stable',
    'dual_read',
    3,
    3,
    NULL
  );
  PERFORM internal.apply_purchase_identity_rollout_operation(
    '31000000-0000-4000-8000-000000000003',
    1,
    'production',
    'qlarqavoqhkuwzmevrmf',
    (SELECT system_identifier::TEXT FROM pg_catalog.PG_CONTROL_SYSTEM()),
    'rollback_authoritative',
    REPEAT('a', 40),
    REPEAT('b', 64),
    REPEAT('c', 64),
    REPEAT('d', 64),
    'stable',
    'authoritative',
    3,
    3,
    '31000000-0000-4000-8000-000000000002'
  );
  PERFORM internal.apply_purchase_identity_rollout_operation(
    '31000000-0000-4000-8000-000000000004',
    1,
    'production',
    'qlarqavoqhkuwzmevrmf',
    (SELECT system_identifier::TEXT FROM pg_catalog.PG_CONTROL_SYSTEM()),
    'rollback_stable',
    REPEAT('e', 40),
    REPEAT('f', 64),
    REPEAT('0', 64),
    REPEAT('1', 64),
    'stable',
    'dual_read',
    3,
    3,
    '31000000-0000-4000-8000-000000000001'
  );

  PERFORM internal.apply_purchase_identity_rollout_operation(
    '31000000-0000-4000-8000-000000000005',
    1,
    'production',
    'qlarqavoqhkuwzmevrmf',
    (SELECT system_identifier::TEXT FROM pg_catalog.PG_CONTROL_SYSTEM()),
    'enable_stable',
    REPEAT('2', 40),
    REPEAT('3', 64),
    REPEAT('4', 64),
    REPEAT('5', 64),
    'legacy',
    'dual_read',
    3,
    3,
    NULL
  );
  BEGIN
    PERFORM internal.apply_purchase_identity_rollout_operation(
      '31000000-0000-4000-8000-000000000006',
      1,
      'production',
      'qlarqavoqhkuwzmevrmf',
      (SELECT system_identifier::TEXT FROM pg_catalog.PG_CONTROL_SYSTEM()),
      'rollback_stable',
      REPEAT('6', 40),
      REPEAT('7', 64),
      REPEAT('8', 64),
      REPEAT('e', 64),
      'stable',
      'dual_read',
      3,
      3,
      '31000000-0000-4000-8000-000000000001'
    );
    RAISE EXCEPTION 'a consumed rollback reference was reused';
  EXCEPTION
    WHEN unique_violation THEN NULL;
  END;

  SELECT * INTO current_config
  FROM internal.purchase_identity_rollout_config AS config
  WHERE config.config_key = 'current';
  IF current_config.principal_mode <> 'stable'
     OR current_config.account_grant_mode <> 'dual_read'
     OR current_config.minimum_client_protocol <> 3 THEN
    RAISE EXCEPTION 'failed rollback reuse changed rollout state';
  END IF;

  PERFORM internal.apply_purchase_identity_rollout_operation(
    '31000000-0000-4000-8000-000000000007',
    1,
    'production',
    'qlarqavoqhkuwzmevrmf',
    (SELECT system_identifier::TEXT FROM pg_catalog.PG_CONTROL_SYSTEM()),
    'rollback_stable',
    REPEAT('a', 40),
    REPEAT('b', 64),
    REPEAT('c', 64),
    REPEAT('f', 64),
    'stable',
    'dual_read',
    3,
    3,
    '31000000-0000-4000-8000-000000000005'
  );

  SELECT * INTO current_config
  FROM internal.purchase_identity_rollout_config AS config
  WHERE config.config_key = 'current';
  IF current_config.principal_mode <> 'legacy'
     OR current_config.account_grant_mode <> 'dual_read'
     OR current_config.minimum_client_protocol <> 3
     OR (
       SELECT COUNT(*)
       FROM internal.purchase_identity_rollout_operations
     ) <> 6 THEN
    RAISE EXCEPTION 'rollout sequence did not finish in the safe legacy state';
  END IF;
END;
$rollout_control$;

SET LOCAL ROLE service_role;
DO $service_denial$
BEGIN
  BEGIN
    PERFORM internal.apply_purchase_identity_rollout_operation(
      '31000000-0000-4000-8000-000000000008',
      1,
      'production',
      'qlarqavoqhkuwzmevrmf',
      (SELECT system_identifier::TEXT FROM pg_catalog.PG_CONTROL_SYSTEM()),
      'enable_stable',
      REPEAT('1', 40),
      REPEAT('2', 64),
      REPEAT('3', 64),
      REPEAT('4', 64),
      'legacy',
      'dual_read',
      3,
      3,
      NULL
    );
    RAISE EXCEPTION 'service role invoked the owner-only rollout routine';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;
END;
$service_denial$;
RESET ROLE;

SELECT extensions.pass(
  'purchase identity rollout is owner-only, versioned, replay-safe, and reversible one axis at a time'
);
SELECT * FROM extensions.finish();
ROLLBACK;
