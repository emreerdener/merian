SET lock_timeout = '5s';
SET statement_timeout = '30s';

-- Collection synchronization uses SECURITY INVOKER routines. Grant only the
-- operations exercised by its guarded upsert, membership delta, and owner
-- join; owner reassignment remains impossible because UPDATE stays column-only.
GRANT SELECT, INSERT, DELETE ON TABLE public.collections TO service_role;
GRANT SELECT ON TABLE public.scans TO service_role;
GRANT SELECT, INSERT, DELETE ON TABLE public.collection_scans TO service_role;

RESET statement_timeout;
RESET lock_timeout;
