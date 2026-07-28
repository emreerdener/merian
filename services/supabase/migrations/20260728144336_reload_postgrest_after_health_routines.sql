-- The preceding migrations add service-only health RPCs consumed through the
-- Data API. Request an explicit cache refresh so a successful database push
-- cannot leave scheduled monitors observing a stale function signature.
NOTIFY pgrst, 'reload schema';
