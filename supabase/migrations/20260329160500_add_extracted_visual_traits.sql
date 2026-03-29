-- Migration to add extracted_visual_traits to scans
ALTER TABLE public.scans
ADD COLUMN extracted_visual_traits text[] DEFAULT '{}'::text[];
