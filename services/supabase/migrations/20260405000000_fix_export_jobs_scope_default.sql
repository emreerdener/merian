-- The export_scope column was created with DEFAULT 'user', but the valid enum values
-- enforced by request-export-dwca are 'personal' and 'global'. Any direct DB insert
-- that omits export_scope (admin scripts, future code paths) would silently produce an
-- invalid scope that export-dwca cannot process. This migration corrects the default.
ALTER TABLE public.export_jobs
  ALTER COLUMN export_scope SET DEFAULT 'personal';
