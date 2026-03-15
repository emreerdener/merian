-- Migration: remove_legacy_scans_remaining
-- Drops the deprecated scans_remaining_today column as limits are now enforced locally on iOS by UsageManager.

ALTER TABLE public.users
DROP COLUMN IF EXISTS scans_remaining_today;
