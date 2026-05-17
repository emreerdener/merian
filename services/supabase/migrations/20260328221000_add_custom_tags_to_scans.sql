-- Add a custom tags text array to support the new Custom Tags UI element on the client payload. 
-- Will be used exclusively as user-specified filters for the offline-library component.
ALTER TABLE public.scans
  ADD COLUMN custom_tags TEXT[] NOT NULL DEFAULT '{}';
