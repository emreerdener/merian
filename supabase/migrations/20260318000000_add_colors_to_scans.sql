-- Add colors array to scans for better semantic search indexing natively
ALTER TABLE public.scans ADD COLUMN IF NOT EXISTS colors TEXT[] NOT NULL DEFAULT '{}';
