-- Migration: 20260405000002_add_pending_storage_deletions_index.sql
-- Description: Add composite index on pending_storage_deletions for efficient
-- background polling by status and target_user_id. Without this index, any
-- cleanup job processing pending deletions performs a full table scan.
--
-- CONCURRENTLY is intentionally omitted because fresh Supabase migration
-- replays execute through a statement pipeline.

CREATE INDEX IF NOT EXISTS idx_pending_storage_deletions_status_user
ON public.pending_storage_deletions (status, target_user_id, created_at);
