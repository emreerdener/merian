-- Add system-owned media lifecycle events separately from the state-machine
-- migration. PostgreSQL enum values must be committed before later statements
-- can safely use them in constraints, functions, and seed writes.

ALTER TYPE public.explore_notification_type
    ADD VALUE IF NOT EXISTS 'media_missing';

ALTER TYPE public.explore_notification_type
    ADD VALUE IF NOT EXISTS 'media_restored';
