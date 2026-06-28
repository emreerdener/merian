-- Persist the capture zoom factor in cloud scan rows so server-side features
-- such as Insight chat can use the same capture-quality context shown locally.
ALTER TABLE public.scans
  ADD COLUMN IF NOT EXISTS zoom_factor DOUBLE PRECISION;
