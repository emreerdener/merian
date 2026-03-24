-- Migration: 20260324000000_add_historical_sync_index.sql
-- Description: Add compound (user_id, timestamp DESC) index to accelerate paginated
-- historical sync queries issued by syncHistoricalScansDown.
--
-- Without this index, a query of the form:
--   WHERE user_id = $1 ORDER BY timestamp DESC LIMIT n OFFSET m
-- hits the existing idx_scans_user_id (user_id only), fetches ALL rows for that user,
-- then sorts them by timestamp in a second pass. For a user with 10,000 scans this
-- means re-sorting 10k rows on every page — O(n log n) per page, O(n² log n) total.
--
-- With the compound index Postgres can satisfy both the filter and the ORDER BY in a
-- single index-only scan, making each page O(page_size) regardless of library size.

CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_scans_user_id_timestamp
ON public.scans (user_id, timestamp DESC);
