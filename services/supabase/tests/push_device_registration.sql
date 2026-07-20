\set ON_ERROR_STOP on

BEGIN;
SELECT extensions.plan(1);

INSERT INTO public.users (id, email)
VALUES (
  '00000000-0000-0000-0000-000000000401',
  'push-device-contract@naturebook.invalid'
);

INSERT INTO public.user_push_devices (
  user_id,
  device_token,
  platform,
  environment
)
VALUES (
  '00000000-0000-0000-0000-000000000401',
  REPEAT('a', 64),
  'ios',
  'sandbox'
);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.user_push_devices
    WHERE user_id = '00000000-0000-0000-0000-000000000401'
      AND device_token = REPEAT('a', 64)
  ) THEN
    RAISE EXCEPTION 'valid APNs token was not registered';
  END IF;

  BEGIN
    INSERT INTO public.user_push_devices (
      user_id, device_token, platform, environment
    ) VALUES (
      '00000000-0000-0000-0000-000000000401',
      REPEAT('b', 31),
      'ios',
      'sandbox'
    );
    RAISE EXCEPTION 'short APNs token unexpectedly passed validation';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO public.user_push_devices (
      user_id, device_token, platform, environment
    ) VALUES (
      '00000000-0000-0000-0000-000000000401',
      REPEAT('c', 513),
      'ios',
      'sandbox'
    );
    RAISE EXCEPTION 'long APNs token unexpectedly passed validation';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;

  BEGIN
    INSERT INTO public.user_push_devices (
      user_id, device_token, platform, environment
    ) VALUES (
      '00000000-0000-0000-0000-000000000401',
      REPEAT('d', 63) || 'g',
      'ios',
      'sandbox'
    );
    RAISE EXCEPTION 'non-hex APNs token unexpectedly passed validation';
  EXCEPTION WHEN check_violation THEN
    NULL;
  END;
END;
$$;

SELECT extensions.pass(
  'APNs device token accepts valid hex and rejects invalid length or format'
);
SELECT * FROM extensions.finish();
ROLLBACK;
