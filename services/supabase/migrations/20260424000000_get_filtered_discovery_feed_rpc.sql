-- Add RPC to filter discovery feed by excluding blocked users directly in SQL
-- Resolves JS memory bloat when a user has many blocks

CREATE OR REPLACE FUNCTION get_filtered_discovery_feed(
  self_id uuid,
  max_limit int
)
RETURNS SETOF scans
LANGUAGE sql
STABLE
AS $$
  SELECT s.*
  FROM scans s
  JOIN users u ON s.user_id = u.id
  WHERE s.geoprivacy = 'open'
    AND s.is_live_capture = true
    AND u.is_shadowbanned = false
    AND s.user_id != self_id
    AND s.image_storage_urls != '{}'
    AND NOT EXISTS (
      SELECT 1 FROM user_blocks ub
      WHERE ub.blocker_id = self_id AND ub.blocked_id = s.user_id
    )
  ORDER BY s.timestamp DESC
  LIMIT max_limit;
$$;
