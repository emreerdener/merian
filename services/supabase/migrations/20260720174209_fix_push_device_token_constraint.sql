-- PostgreSQL regex repetition bounds are limited to 255. The original
-- combined 32-to-512 interval therefore raised "invalid repetition count(s)" whenever
-- user_push_devices was written. Keep the same validation policy by checking
-- the token's format and length independently.
ALTER TABLE public.user_push_devices
    DROP CONSTRAINT IF EXISTS user_push_devices_device_token_check;

ALTER TABLE public.user_push_devices
    ADD CONSTRAINT user_push_devices_device_token_format_check
        CHECK (device_token ~ '^[A-Fa-f0-9]+$') NOT VALID,
    ADD CONSTRAINT user_push_devices_device_token_length_check
        CHECK (CHAR_LENGTH(device_token) BETWEEN 32 AND 512) NOT VALID;

ALTER TABLE public.user_push_devices
    VALIDATE CONSTRAINT user_push_devices_device_token_format_check,
    VALIDATE CONSTRAINT user_push_devices_device_token_length_check;

COMMENT ON CONSTRAINT user_push_devices_device_token_format_check
    ON public.user_push_devices IS
    'Requires an APNs device token containing only hexadecimal characters.';

COMMENT ON CONSTRAINT user_push_devices_device_token_length_check
    ON public.user_push_devices IS
    'Requires an APNs device token between 32 and 512 characters without exceeding PostgreSQL regex repetition limits.';

NOTIFY pgrst, 'reload schema';
