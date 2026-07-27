-- Trip-level educational context is optional. Keep it absent for these two
-- outings so clients omit the "Why it matters" card by default.
UPDATE public.field_trip_templates
SET guide_why_it_matters = NULL
WHERE slug IN ('backyard_safari', 'park_pollinators')
  AND guide_why_it_matters IS NOT NULL;
