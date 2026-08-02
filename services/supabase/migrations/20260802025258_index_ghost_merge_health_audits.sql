-- Keep recurring aggregate Ghost-merge health audits bounded as receipt
-- history grows. The predicates exactly match the monitor's hot paths.

SET lock_timeout = '10s';
SET statement_timeout = '2min';

CREATE INDEX ghost_profile_merge_recent_receipts_idx
    ON internal.ghost_profile_merge_handoffs (created_at)
    WHERE status IN ('prepared', 'merged', 'expired');

CREATE INDEX ghost_profile_merge_recent_destinations_idx
    ON internal.ghost_profile_merge_handoffs (merged_at, target_user_id)
    WHERE status = 'merged';

COMMENT ON INDEX internal.ghost_profile_merge_recent_receipts_idx IS
'Bounds rolling receipt-status health audits without indexing superseded receipts.';
COMMENT ON INDEX internal.ghost_profile_merge_recent_destinations_idx IS
'Bounds rolling destination RevenueCat queue audits for completed Ghost merges.';

RESET lock_timeout;
RESET statement_timeout;
