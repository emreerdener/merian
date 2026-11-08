BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();

-- Pure clock boundary checks, not an installed policy or byte attestation.
CREATE FUNCTION pg_temp.retention_interval(started JSONB,verified JSONB,adopted BIGINT)
RETURNS VOID LANGUAGE PLPGSQL AS $$
DECLARE policy internal.initial_cpm_photo_retention_policies;
BEGIN
 policy.verification_max_duration_ms:=150000;
 policy.verification_max_age_ms:=30000;
 policy.clock_skew_ms:=1000;
 PERFORM internal.assert_initial_cpm_retention_interval_v1(policy,started,verified,adopted);
END $$;

SELECT extensions.lives_ok($$SELECT pg_temp.retention_interval('850000','1000000',1000000)$$,'whole interval accepts exact maximum');
SELECT extensions.throws_ok($$SELECT pg_temp.retention_interval('849999','1000000',1000000)$$,'22023','initial_completion_retention_verification_invalid','whole interval denies one millisecond beyond maximum');
SELECT extensions.lives_ok($$SELECT pg_temp.retention_interval('970000','970000',1000000)$$,'age accepts exact maximum');
SELECT extensions.throws_ok($$SELECT pg_temp.retention_interval('969999','969999',1000000)$$,'22023','initial_completion_retention_verification_invalid','age denies one millisecond beyond maximum');
SELECT extensions.lives_ok($$SELECT pg_temp.retention_interval('1001000','1001000',1000000)$$,'skew accepts exact maximum');
SELECT extensions.throws_ok($$SELECT pg_temp.retention_interval('1001001','1001001',1000000)$$,'22023','initial_completion_retention_verification_invalid','skew denies one millisecond beyond maximum');
SELECT extensions.throws_ok($$SELECT pg_temp.retention_interval('1000001','1000000',1000000)$$,'22023','initial_completion_retention_verification_invalid','reversed interval denied');
SELECT extensions.throws_ok($$SELECT pg_temp.retention_interval('1000000','1000000',NULL)$$,'22023','initial_completion_retention_verification_invalid','missing adoption clock denied');
SELECT extensions.throws_ok($$SELECT pg_temp.retention_interval('1000000','1000000',9007199254740992)$$,'22023','initial_completion_retention_verification_invalid','unsafe adoption integer denied');
SELECT extensions.throws_ok($$SELECT pg_temp.retention_interval('9007199254740992','9007199254740992',9007199254740991)$$,'22023','initial_completion_retention_verification_invalid','unsafe proof integer denied');
SELECT extensions.throws_ok($$SELECT pg_temp.retention_interval('1000000.5','1000001',1000001)$$,'22023','initial_completion_retention_verification_invalid','fractional start denied');
SELECT extensions.throws_ok($$SELECT pg_temp.retention_interval('null','1000000',1000000)$$,'22023','initial_completion_retention_verification_invalid','JSON null start denied');
SELECT extensions.throws_ok($$SELECT pg_temp.retention_interval('1000000','"1000000"',1000000)$$,'22023','initial_completion_retention_verification_invalid','text finish denied');
SELECT extensions.throws_ok($$SELECT pg_temp.retention_interval('0','1000000',1000000)$$,'22023','initial_completion_retention_verification_invalid','zero start denied');
SELECT extensions.is((SELECT count(*) FROM internal.initial_cpm_photo_retention_policies),0::BIGINT,'no terminal retention policy installed');
SELECT * FROM extensions.finish();
ROLLBACK;
