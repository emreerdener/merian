-- The Photos share-sheet import prototype was removed from the shipped app and
-- repo source. Its queue endpoint is retired, so the companion visibility table
-- no longer has a writer or reader.

DROP TABLE IF EXISTS public.scan_import_jobs;
