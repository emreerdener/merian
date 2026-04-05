-- Migration: 20260405000003_add_failed_scan_ingestions.sql
-- Description: Dead-letter table for background scan ingestion failures.
--
-- When identify/index.ts fires runBackgroundIngestion() and the insertScan()
-- call fails (FK violation, DB timeout, network partition), the iOS client has
-- already received a 200 with the AI result. Without this table the failure is
-- only visible in logs — the scan is permanently missing from the server DB,
-- breaking multi-device sync and DwC-A exports for that user.
--
-- Ops workflow: query this table to find affected users, then replay insertScan
-- by re-invoking the identify function with the same client_scan_id. The
-- ignoreDuplicates: true idempotency guard in insertScan makes replay safe.

CREATE TABLE public.failed_scan_ingestions (
  id             UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  scan_id        TEXT        NOT NULL,
  user_id        UUID        NOT NULL,
  error_message  TEXT,
  failed_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for ops queries: "show me all failed scans for user X" and
-- "show me recent failures regardless of user" (monitoring sweep).
CREATE INDEX idx_failed_scan_ingestions_user_id
  ON public.failed_scan_ingestions (user_id, failed_at DESC);

CREATE INDEX idx_failed_scan_ingestions_failed_at
  ON public.failed_scan_ingestions (failed_at DESC);

-- Service-role only. No RLS policies needed — this table is never read
-- by the client SDK; only the edge function (service role) writes to it,
-- and ops queries it directly via the Supabase dashboard.
ALTER TABLE public.failed_scan_ingestions ENABLE ROW LEVEL SECURITY;
