-- Forest Edges was placeholder content. Retire it from active Field Trip
-- surfaces without deleting progress, publications, scans, or evidence.
UPDATE public.field_trip_templates
SET is_active = FALSE,
    updated_at = NOW()
WHERE slug = 'forest_edges'
  AND is_active = TRUE;
