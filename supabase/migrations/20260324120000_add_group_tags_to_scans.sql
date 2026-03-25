-- Add group_tags array to scans for categorical search (e.g. "bird", "songbird").
-- Populated by the identify edge function via Gemini's group_tags output field.
ALTER TABLE public.scans ADD COLUMN IF NOT EXISTS group_tags TEXT[] NOT NULL DEFAULT '{}';
